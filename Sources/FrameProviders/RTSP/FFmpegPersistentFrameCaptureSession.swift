import Darwin
import Foundation

actor FFmpegPersistentFrameCaptureSession: FrameProvider {
    nonisolated let id: UUID
    let configuration: CameraDefinition

    private let source: FrameSource
    private let ffmpegPath: String
    private let frameStore = LatestCapturedFrameStore()
    private let chunkSize = 64 * 1024
    private let stallTimeout: TimeInterval = 10
    private let startTimeout: TimeInterval = 12

    private var processResources: FFmpegProcessResources?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var parser: RawVideoFrameParser
    private var desiredRunning = false
    private var providerStatus: FrameProviderStatus
    private var lastFrameAt: Date?
    private var frameSequence: UInt64 = 0
    private var consecutiveReconnectAttempts = 0
    private var restartCount = 0
    private var currentGeneration: Int = 0
    private var firstFrameContinuation: CheckedContinuation<Void, Error>?
    private var stderrLines: [String] = []

    init(source: FrameSource, ffmpegPath: String) {
        self.id = source.camera.id
        self.configuration = source.camera
        self.source = source
        self.ffmpegPath = ffmpegPath
        self.parser = RawVideoFrameParser(frameSize: source.frameWidth * source.frameHeight * 4)
        self.providerStatus = FrameProviderStatus.inactive(
            sourceID: source.camera.id,
            providerType: .ffmpeg,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "FFmpeg RTSP",
            state: .idle
        )
    }

    func start() async throws {
        guard !desiredRunning else { return }
        desiredRunning = true
        try await launchProcess(preferVideoToolbox: true, isRetry: false)
    }

    func stop() async {
        desiredRunning = false
        reconnectTask?.cancel()
        reconnectTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        firstFrameContinuation?.resume(throwing: SessionStopError.cancelled)
        firstFrameContinuation = nil
        await stopCurrentProcess(markAsStopped: true)
        await frameStore.reset()
        parser.reset()
        lastFrameAt = nil
        frameSequence = 0
        stderrLines.removeAll()
    }

    func getSnapshot() async throws -> CapturedFrame {
        if let frame = await frameStore.current() {
            return frame
        }

        throw FrameProviderError.frameUnavailable
    }

    func latestFrame() async -> CapturedFrame? {
        await frameStore.current()
    }

    func getStatus() async -> FrameProviderStatus {
        providerStatus
    }

    private func launchProcess(preferVideoToolbox: Bool, isRetry: Bool) async throws {
        guard desiredRunning else { return }
        guard processResources == nil else { return }
        await resumeFirstFrameContinuation(with: SessionStopError.cancelled)

        currentGeneration += 1
        parser.reset()
        stderrLines.removeAll()

        let generation = currentGeneration
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = makeArguments(preferVideoToolbox: preferVideoToolbox)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(
                    generation: generation,
                    status: process.terminationStatus
                )
            }
        }

        providerStatus = FrameProviderStatus(
            sourceID: id,
            providerType: .ffmpeg,
            state: .starting,
            lastFrameAt: lastFrameAt,
            lastFrameSequence: frameSequence == 0 ? nil : frameSequence,
            lastError: nil,
            restartCount: restartCount,
            configuredFPS: source.configuredFPS,
            isActive: false,
            isReconnecting: false,
            sessionModeLabel: "FFmpeg RTSP",
            usingVideoToolbox: preferVideoToolbox,
            isUsingVideoToolboxFallback: !preferVideoToolbox,
            processIdentifier: nil,
            diagnosticMessage: "Starting persistent FFmpeg session",
            webViewNavigationStatus: nil,
            webViewWindowStatus: nil,
            screenCaptureStatus: nil,
            loadedURL: nil,
            windowTitle: nil,
            screenCapturePermissionDenied: false
        )

        do {
            try process.run()
        } catch {
            if preferVideoToolbox {
                AppLog.ffmpeg.warning("Failed to start FFmpeg with VideoToolbox for source \(self.id.uuidString, privacy: .public). Retrying without hardware decoding.")
                try await launchProcess(preferVideoToolbox: false, isRetry: true)
                return
            }

            providerStatus = FrameProviderStatus.inactive(
                sourceID: id,
                providerType: .ffmpeg,
                configuredFPS: source.configuredFPS,
                sessionModeLabel: "FFmpeg RTSP",
                error: error.localizedDescription,
                state: .failed
            )
            throw error
        }

        let resources = FFmpegProcessResources(
            process: process,
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading
        )
        processResources = resources

        AppLog.ffmpeg.info("Started FFmpeg PID \(process.processIdentifier, privacy: .public) for source \(self.id.uuidString, privacy: .public), hardware decode: \(preferVideoToolbox, privacy: .public)")

        providerStatus = FrameProviderStatus(
            sourceID: id,
            providerType: .ffmpeg,
            state: .waitingForFrame,
            lastFrameAt: lastFrameAt,
            lastFrameSequence: frameSequence == 0 ? nil : frameSequence,
            lastError: nil,
            restartCount: restartCount,
            configuredFPS: source.configuredFPS,
            isActive: true,
            isReconnecting: false,
            sessionModeLabel: "FFmpeg RTSP",
            usingVideoToolbox: preferVideoToolbox,
            isUsingVideoToolboxFallback: !preferVideoToolbox,
            processIdentifier: process.processIdentifier,
            diagnosticMessage: "Connected and reading raw BGRA frames",
            webViewNavigationStatus: nil,
            webViewWindowStatus: nil,
            screenCaptureStatus: nil,
            loadedURL: nil,
            windowTitle: nil,
            screenCapturePermissionDenied: false
        )

        stdoutTask = makeStdoutTask(resources: resources, generation: generation)
        stderrTask = makeStderrTask(resources: resources, generation: generation)
        watchdogTask = makeWatchdogTask(generation: generation)

        do {
            try await waitForFirstFrame()
            consecutiveReconnectAttempts = 0
            if isRetry {
                AppLog.ffmpeg.notice("FFmpeg fallback without VideoToolbox succeeded for source \(self.id.uuidString, privacy: .public)")
            }
        } catch {
            await stopCurrentProcess(markAsStopped: false)
            if preferVideoToolbox {
                AppLog.ffmpeg.warning("FFmpeg did not yield frames with VideoToolbox for source \(self.id.uuidString, privacy: .public). Retrying without hardware decoding.")
                try await launchProcess(preferVideoToolbox: false, isRetry: true)
                return
            }

            providerStatus = FrameProviderStatus.inactive(
                sourceID: id,
                providerType: .ffmpeg,
                configuredFPS: source.configuredFPS,
                sessionModeLabel: "FFmpeg RTSP",
                error: error.localizedDescription,
                state: .failed
            )
            throw error
        }
    }

    private func makeArguments(preferVideoToolbox: Bool) -> [String] {
        var arguments = [
            "-hide_banner",
            "-loglevel", "warning",
            "-rtsp_transport", "tcp"
        ]

        if preferVideoToolbox {
            arguments.append(contentsOf: ["-hwaccel", "videotoolbox"])
        }

        arguments.append(contentsOf: [
            "-i", source.camera.trimmedStreamURL,
            "-map", "0:v:0",
            "-an",
            "-vf", "fps=\(String(format: "%.3f", source.configuredFPS)),scale=\(source.frameWidth):\(source.frameHeight)",
            "-pix_fmt", "bgra",
            "-f", "rawvideo",
            "pipe:1"
        ])

        return arguments
    }

    private func waitForFirstFrame() async throws {
        let startTimeout = self.startTimeout
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(startTimeout * 1_000_000_000))
            await self?.resumeFirstFrameContinuation(with: FFmpegPersistentSessionError.startTimedOut)
        }

        defer { timeoutTask.cancel() }

        try await withCheckedThrowingContinuation { continuation in
            firstFrameContinuation = continuation
        }
    }

    private func makeStdoutTask(resources: FFmpegProcessResources, generation: Int) -> Task<Void, Never> {
        let chunkSize = self.chunkSize

        return Task.detached(priority: .userInitiated) { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let chunk = try resources.stdoutHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                        break
                    }

                    await self?.consumeStdoutChunk(chunk, generation: generation)
                }
            } catch {
                await self?.handleReadFailure(error, generation: generation)
            }
        }
    }

    private func makeStderrTask(resources: FFmpegProcessResources, generation: Int) -> Task<Void, Never> {
        Task.detached(priority: .utility) { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let chunk = try resources.stderrHandle.read(upToCount: 4096), !chunk.isEmpty else {
                        break
                    }

                    let text = String(decoding: chunk, as: UTF8.self)
                    await self?.consumeStderr(text, generation: generation)
                }
            } catch {
                await self?.consumeStderr("stderr read failure: \(error.localizedDescription)", generation: generation)
            }
        }
    }

    private func makeWatchdogTask(generation: Int) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.checkForStall(generation: generation)
            }
        }
    }

    private func consumeStdoutChunk(_ chunk: Data, generation: Int) async {
        guard generation == currentGeneration else { return }

        let frames = parser.append(chunk)
        guard !frames.isEmpty else { return }

        for frameData in frames {
            do {
                let cgImage = try BGRACGImageConverter.makeImage(
                    from: frameData,
                    width: source.frameWidth,
                    height: source.frameHeight
                )

                frameSequence += 1
                let capturedAt = Date()
                lastFrameAt = capturedAt

                let frame = CapturedFrame(
                    sourceID: id,
                    providerType: .ffmpeg,
                    image: cgImage,
                    capturedAt: capturedAt,
                    sequence: frameSequence,
                    pixelSize: CGSize(width: source.frameWidth, height: source.frameHeight)
                )
                await frameStore.replace(with: frame)
            } catch {
                providerStatus = updatedStatus(
                    state: .failed,
                    error: error.localizedDescription,
                    diagnostic: "Failed to decode BGRA frame"
                )
            }
        }

        providerStatus = updatedStatus(
            state: .running,
            error: nil,
            diagnostic: "Receiving persistent FFmpeg frames"
        )

        await resumeFirstFrameContinuation(with: nil)
    }

    private func consumeStderr(_ text: String, generation: Int) async {
        guard generation == currentGeneration else { return }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else { return }

        stderrLines.append(contentsOf: lines)
        if stderrLines.count > 12 {
            stderrLines.removeFirst(stderrLines.count - 12)
        }
    }

    private func handleReadFailure(_ error: Error, generation: Int) async {
        guard generation == currentGeneration else { return }
        AppLog.ffmpeg.error("stdout read failed for source \(self.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        await scheduleReconnect(reason: "Read failure: \(error.localizedDescription)")
    }

    private func handleTermination(generation: Int, status: Int32) async {
        guard generation == currentGeneration else { return }
        AppLog.ffmpeg.warning("FFmpeg PID \(self.processResources?.process.processIdentifier ?? 0, privacy: .public) terminated for source \(self.id.uuidString, privacy: .public) with status \(status, privacy: .public)")
        await scheduleReconnect(reason: "FFmpeg exited with status \(status)")
    }

    private func checkForStall(generation: Int) async {
        guard generation == currentGeneration else { return }
        guard desiredRunning else { return }
        guard processResources != nil else { return }
        guard let lastFrameAt else { return }

        let age = Date().timeIntervalSince(lastFrameAt)
        if age >= stallTimeout {
            AppLog.ffmpeg.warning("No frames received for \(age, privacy: .public)s on source \(self.id.uuidString, privacy: .public); restarting session.")
            await scheduleReconnect(reason: "No new frames for \(Int(age)) seconds")
        }
    }

    private func scheduleReconnect(reason: String) async {
        guard desiredRunning else { return }
        guard reconnectTask == nil else { return }

        consecutiveReconnectAttempts += 1
        let delay = ReconnectBackoffSequence.delay(forAttempt: consecutiveReconnectAttempts)

        providerStatus = updatedStatus(
            state: .reconnecting,
            error: reason,
            diagnostic: "Reconnecting in \(delay.formattedAge)"
        )

        await stopCurrentProcess(markAsStopped: false)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.performReconnect()
        }
    }

    private func performReconnect() async {
        reconnectTask = nil
        guard desiredRunning else { return }
        restartCount += 1

        do {
            try await launchProcess(
                preferVideoToolbox: !(providerStatus.isUsingVideoToolboxFallback),
                isRetry: false
            )
        } catch {
            AppLog.ffmpeg.error("Reconnect failed for source \(self.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await scheduleReconnect(reason: error.localizedDescription)
        }
    }

    private func stopCurrentProcess(markAsStopped: Bool) async {
        stdoutTask?.cancel()
        stderrTask?.cancel()
        watchdogTask?.cancel()
        stdoutTask = nil
        stderrTask = nil
        watchdogTask = nil

        guard let resources = processResources else {
            if markAsStopped {
                providerStatus = updatedStatus(state: .stopped, error: nil, diagnostic: "Stopped")
            }
            return
        }

        processResources = nil

        resources.stdoutHandle.readabilityHandler = nil
        resources.stderrHandle.readabilityHandler = nil

        if resources.process.isRunning {
            resources.process.terminate()
            try? await Task.sleep(nanoseconds: 500_000_000)

            if resources.process.isRunning {
                kill(resources.process.processIdentifier, SIGKILL)
            }
        }

        try? resources.stdoutHandle.close()
        try? resources.stderrHandle.close()

        if markAsStopped {
            providerStatus = updatedStatus(state: .stopped, error: nil, diagnostic: "Stopped")
        }
    }

    private func resumeFirstFrameContinuation(with error: Error?) async {
        guard let continuation = firstFrameContinuation else { return }
        firstFrameContinuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func updatedStatus(
        state: FrameProviderState,
        error: String?,
        diagnostic: String
    ) -> FrameProviderStatus {
        FrameProviderStatus(
            sourceID: id,
            providerType: .ffmpeg,
            state: state,
            lastFrameAt: lastFrameAt,
            lastFrameSequence: frameSequence == 0 ? nil : frameSequence,
            lastError: error ?? stderrLines.last,
            restartCount: restartCount,
            configuredFPS: source.configuredFPS,
            isActive: processResources?.process.isRunning == true,
            isReconnecting: state == .reconnecting,
            sessionModeLabel: "FFmpeg RTSP",
            usingVideoToolbox: providerStatus.usingVideoToolbox,
            isUsingVideoToolboxFallback: providerStatus.isUsingVideoToolboxFallback,
            processIdentifier: processResources?.process.processIdentifier,
            diagnosticMessage: diagnostic,
            webViewNavigationStatus: nil,
            webViewWindowStatus: nil,
            screenCaptureStatus: nil,
            loadedURL: nil,
            windowTitle: nil,
            screenCapturePermissionDenied: false
        )
    }
}

private final class FFmpegProcessResources: @unchecked Sendable {
    let process: Process
    let stdoutHandle: FileHandle
    let stderrHandle: FileHandle

    init(process: Process, stdoutHandle: FileHandle, stderrHandle: FileHandle) {
        self.process = process
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
    }
}

private enum FFmpegPersistentSessionError: LocalizedError {
    case startTimedOut

    var errorDescription: String? {
        switch self {
        case .startTimedOut:
            return "FFmpeg did not deliver the first frame in time."
        }
    }
}

private enum SessionStopError: LocalizedError {
    case cancelled
}

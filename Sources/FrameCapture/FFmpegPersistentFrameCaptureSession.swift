import Darwin
import Foundation

actor FFmpegPersistentFrameCaptureSession: FrameCaptureSession {
    nonisolated let cameraID: UUID

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
    private var sessionState: CaptureSessionState
    private var lastFrameAt: Date?
    private var frameSequence: UInt64 = 0
    private var consecutiveReconnectAttempts = 0
    private var restartCount = 0
    private var currentGeneration: Int = 0
    private var firstFrameContinuation: CheckedContinuation<Void, Error>?
    private var stderrLines: [String] = []

    init(source: FrameSource, ffmpegPath: String) {
        self.cameraID = source.camera.id
        self.source = source
        self.ffmpegPath = ffmpegPath
        self.parser = RawVideoFrameParser(frameSize: source.frameWidth * source.frameHeight * 4)
        self.sessionState = CaptureSessionState.inactive(
            cameraID: source.camera.id,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "FFmpeg RTSP"
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

    func latestFrame() async -> CapturedFrame? {
        await frameStore.current()
    }

    func state() async -> CaptureSessionState {
        sessionState
    }

    private func launchProcess(preferVideoToolbox: Bool, isRetry: Bool) async throws {
        guard desiredRunning else { return }
        guard processResources == nil else { return }

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

        sessionState = CaptureSessionState(
            cameraID: cameraID,
            status: .starting,
            lastErrorMessage: nil,
            lastFrameAt: lastFrameAt,
            lastFrameSequence: frameSequence == 0 ? nil : frameSequence,
            isActive: false,
            isReconnecting: false,
            restartCount: restartCount,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "FFmpeg RTSP",
            usingVideoToolbox: preferVideoToolbox,
            isUsingVideoToolboxFallback: !preferVideoToolbox,
            processIdentifier: nil,
            diagnosticMessage: "Starting persistent FFmpeg session"
        )

        do {
            try process.run()
        } catch {
            if preferVideoToolbox {
                AppLog.ffmpeg.warning("Failed to start FFmpeg with VideoToolbox for camera \(self.cameraID.uuidString, privacy: .public). Retrying without hardware decoding.")
                try await launchProcess(preferVideoToolbox: false, isRetry: true)
                return
            }

            sessionState = CaptureSessionState.inactive(
                cameraID: cameraID,
                configuredFPS: source.configuredFPS,
                sessionModeLabel: "FFmpeg RTSP",
                error: error.localizedDescription,
                status: .error
            )
            throw error
        }

        let resources = FFmpegProcessResources(
            process: process,
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading
        )
        processResources = resources

        AppLog.ffmpeg.info("Started FFmpeg PID \(process.processIdentifier, privacy: .public) for camera \(self.cameraID.uuidString, privacy: .public), hardware decode: \(preferVideoToolbox, privacy: .public)")

        sessionState = CaptureSessionState(
            cameraID: cameraID,
            status: .capturing,
            lastErrorMessage: nil,
            lastFrameAt: lastFrameAt,
            lastFrameSequence: frameSequence == 0 ? nil : frameSequence,
            isActive: true,
            isReconnecting: false,
            restartCount: restartCount,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "FFmpeg RTSP",
            usingVideoToolbox: preferVideoToolbox,
            isUsingVideoToolboxFallback: !preferVideoToolbox,
            processIdentifier: process.processIdentifier,
            diagnosticMessage: "Connected and reading raw BGRA frames"
        )

        stdoutTask = makeStdoutTask(resources: resources, generation: generation)
        stderrTask = makeStderrTask(resources: resources, generation: generation)
        watchdogTask = makeWatchdogTask(generation: generation)

        do {
            try await waitForFirstFrame()
            consecutiveReconnectAttempts = 0
            if isRetry {
                AppLog.ffmpeg.notice("FFmpeg fallback without VideoToolbox succeeded for camera \(self.cameraID.uuidString, privacy: .public)")
            }
        } catch {
            await stopCurrentProcess(markAsStopped: false)
            if preferVideoToolbox {
                AppLog.ffmpeg.warning("FFmpeg did not yield frames with VideoToolbox for camera \(self.cameraID.uuidString, privacy: .public). Retrying without hardware decoding.")
                try await launchProcess(preferVideoToolbox: false, isRetry: true)
                return
            }

            sessionState = CaptureSessionState.inactive(
                cameraID: cameraID,
                configuredFPS: source.configuredFPS,
                sessionModeLabel: "FFmpeg RTSP",
                error: error.localizedDescription,
                status: .error
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
        return Task.detached(priority: .utility) { [weak self] in
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
        return Task { [weak self] in
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
                    image: cgImage,
                    capturedAt: capturedAt,
                    sourceFrameSequence: frameSequence,
                    pixelSize: CGSize(width: source.frameWidth, height: source.frameHeight)
                )
                await frameStore.replace(with: frame)
            } catch {
                sessionState = updatedState(
                    status: .error,
                    error: error.localizedDescription,
                    diagnostic: "Failed to decode BGRA frame"
                )
            }
        }

        sessionState = updatedState(
            status: .capturing,
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
        AppLog.ffmpeg.error("stdout read failed for camera \(self.cameraID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        await scheduleReconnect(reason: "Read failure: \(error.localizedDescription)")
    }

    private func handleTermination(generation: Int, status: Int32) async {
        guard generation == currentGeneration else { return }
        AppLog.ffmpeg.warning("FFmpeg PID \(self.processResources?.process.processIdentifier ?? 0, privacy: .public) terminated for camera \(self.cameraID.uuidString, privacy: .public) with status \(status, privacy: .public)")
        await scheduleReconnect(reason: "FFmpeg exited with status \(status)")
    }

    private func checkForStall(generation: Int) async {
        guard generation == currentGeneration else { return }
        guard desiredRunning else { return }
        guard processResources != nil else { return }
        guard let lastFrameAt else { return }

        let age = Date().timeIntervalSince(lastFrameAt)
        if age >= stallTimeout {
            AppLog.ffmpeg.warning("No frames received for \(age, privacy: .public)s on camera \(self.cameraID.uuidString, privacy: .public); restarting session.")
            await scheduleReconnect(reason: "No new frames for \(Int(age)) seconds")
        }
    }

    private func scheduleReconnect(reason: String) async {
        guard desiredRunning else { return }
        guard reconnectTask == nil else { return }

        consecutiveReconnectAttempts += 1
        let delay = ReconnectBackoffSequence.delay(forAttempt: consecutiveReconnectAttempts)

        sessionState = updatedState(
            status: .reconnecting,
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
                preferVideoToolbox: !(sessionState.isUsingVideoToolboxFallback),
                isRetry: false
            )
        } catch {
            AppLog.ffmpeg.error("Reconnect failed for camera \(self.cameraID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
                sessionState = updatedState(status: .stopped, error: nil, diagnostic: "Stopped")
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
            sessionState = updatedState(status: .stopped, error: nil, diagnostic: "Stopped")
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

    private func updatedState(
        status: CaptureStatus,
        error: String?,
        diagnostic: String
    ) -> CaptureSessionState {
        CaptureSessionState(
            cameraID: cameraID,
            status: status,
            lastErrorMessage: error ?? stderrLines.last,
            lastFrameAt: lastFrameAt,
            lastFrameSequence: frameSequence == 0 ? nil : frameSequence,
            isActive: processResources?.process.isRunning == true,
            isReconnecting: status == .reconnecting,
            restartCount: restartCount,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "FFmpeg RTSP",
            usingVideoToolbox: sessionState.usingVideoToolbox,
            isUsingVideoToolboxFallback: sessionState.isUsingVideoToolboxFallback,
            processIdentifier: processResources?.process.processIdentifier,
            diagnosticMessage: diagnostic
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

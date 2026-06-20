import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

actor ScreenCaptureFrameSession {
    private let sourceID: UUID
    private let frameStore = LatestCapturedFrameStore()
    private let outputQueue = DispatchQueue(label: "CameraDirector.ScreenCapture.Output", qos: .userInitiated)
    private let providerType: FrameProviderType = .webView

    private var stream: SCStream?
    private var output: ScreenCaptureFrameOutput?
    private var statusMessage = "Idle"
    private var lastError: String?
    private var lastFrameAt: Date?
    private var sequence: UInt64 = 0
    private var isPermissionDenied = false
    private var restartCount = 0

    init(sourceID: UUID) {
        self.sourceID = sourceID
    }

    func start(
        windowID: CGWindowID,
        windowTitle: String,
        configuredFPS: Double,
        width: Int,
        height: Int
    ) async throws {
        if stream != nil {
            return
        }

        let targetWindow = try await findWindow(windowID: windowID, fallbackTitle: windowTitle)
        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, width)
        configuration.height = max(1, height)
        configuration.minimumFrameInterval = CMTime(seconds: 1.0 / max(0.1, configuredFPS), preferredTimescale: 600)
        configuration.queueDepth = 2
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = true
        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = false
        }

        let screenOutput = ScreenCaptureFrameOutput { [weak self] cgImage in
            Task {
                await self?.consumeFrame(image: cgImage)
            }
        }

        let captureStream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        do {
            try addOutput(screenOutput, to: captureStream)
            try await startCapture(for: captureStream)
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed"
            throw error
        }

        stream = captureStream
        output = screenOutput
        statusMessage = "Running"
        lastError = nil
        isPermissionDenied = false
        AppLog.screenCapture.info("Started ScreenCaptureKit for source \(self.sourceID.uuidString, privacy: .public)")
    }

    func stop() async {
        guard let stream else { return }

        do {
            try await stopCapture(for: stream)
        } catch {
            AppLog.screenCapture.error("Failed to stop ScreenCaptureKit for source \(self.sourceID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        self.stream = nil
        output = nil
        statusMessage = "Stopped"
    }

    func latestFrame() async -> CapturedFrame? {
        await frameStore.current()
    }

    func status(configuredFPS: Double) -> ScreenCaptureFrameSessionStatus {
        ScreenCaptureFrameSessionStatus(
            lastFrameAt: lastFrameAt,
            lastFrameSequence: sequence == 0 ? nil : sequence,
            lastError: lastError,
            restartCount: restartCount,
            configuredFPS: configuredFPS,
            statusMessage: statusMessage,
            screenCapturePermissionDenied: isPermissionDenied,
            isActive: stream != nil
        )
    }

    private func consumeFrame(image: CGImage) async {
        sequence += 1
        let frame = CapturedFrame(
            sourceID: sourceID,
            providerType: providerType,
            image: image,
            capturedAt: Date(),
            sequence: sequence,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
        lastFrameAt = frame.capturedAt
        statusMessage = "Receiving frames"
        lastError = nil
        await frameStore.replace(with: frame)
    }

    private func findWindow(windowID: CGWindowID, fallbackTitle: String) async throws -> SCWindow {
        if #available(macOS 14.4, *) {
            let content = try await withCheckedThrowingContinuation { continuation in
                SCShareableContent.getCurrentProcessShareableContent { shareableContent, error in
                    if let shareableContent {
                        continuation.resume(returning: shareableContent)
                    } else {
                        continuation.resume(throwing: error ?? FrameProviderError.screenCaptureWindowUnavailable)
                    }
                }
            }

            if let window = content.windows.first(where: { $0.windowID == windowID || $0.title == fallbackTitle }) {
                return window
            }
        }

        guard ScreenCapturePermissionCenter.requestAccessIfNeeded() else {
            isPermissionDenied = true
            lastError = FrameProviderError.screenCapturePermissionDenied.localizedDescription
            throw FrameProviderError.screenCapturePermissionDenied
        }

        let content = try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { shareableContent, error in
                if let shareableContent {
                    continuation.resume(returning: shareableContent)
                } else {
                    continuation.resume(throwing: error ?? FrameProviderError.screenCaptureWindowUnavailable)
                }
            }
        }

        if let window = content.windows.first(where: { $0.windowID == windowID || $0.title == fallbackTitle }) {
            return window
        }

        throw FrameProviderError.screenCaptureWindowUnavailable
    }

    private func addOutput(_ output: ScreenCaptureFrameOutput, to stream: SCStream) throws {
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
    }

    private func startCapture(for stream: SCStream) async throws {
        try await stream.startCapture()
    }

    private func stopCapture(for stream: SCStream) async throws {
        try await stream.stopCapture()
    }
}

struct ScreenCaptureFrameSessionStatus: Sendable {
    let lastFrameAt: Date?
    let lastFrameSequence: UInt64?
    let lastError: String?
    let restartCount: Int
    let configuredFPS: Double
    let statusMessage: String
    let screenCapturePermissionDenied: Bool
    let isActive: Bool
}

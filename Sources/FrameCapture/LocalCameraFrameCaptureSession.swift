import Foundation

actor LocalCameraFrameCaptureSession: FrameCaptureSession {
    nonisolated let cameraID: UUID

    private let source: FrameSource
    private let deviceProvider: LocalCameraDeviceProvider
    private let frameStore = LatestCapturedFrameStore()
    private var captureSession: AVCaptureCameraSession?
    private var sessionState: CaptureSessionState

    init(source: FrameSource, deviceProvider: LocalCameraDeviceProvider) {
        self.cameraID = source.camera.id
        self.source = source
        self.deviceProvider = deviceProvider
        self.sessionState = CaptureSessionState.inactive(
            cameraID: source.camera.id,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "AVFoundation Local Camera"
        )
    }

    func start() async throws {
        guard captureSession == nil else { return }

        let status = await deviceProvider.authorizationStatus()
        if status != .authorized {
            if status == .notDetermined {
                let granted = await deviceProvider.requestAccess()
                guard granted else {
                    throw LocalCameraStartError.permissionDenied
                }
            } else {
                throw LocalCameraStartError.permissionDenied
            }
        }

        guard let deviceID = source.camera.trimmedLocalDeviceUniqueID else {
            throw LocalCameraStartError.deviceUnavailable
        }

        guard await deviceProvider.deviceExists(uniqueID: deviceID) else {
            throw LocalCameraStartError.deviceUnavailable
        }

        let helper = AVCaptureCameraSession(
            deviceUniqueID: deviceID,
            targetSize: CGSize(width: source.frameWidth, height: source.frameHeight)
        )

        helper.onFrame = { [weak self] frame in
            Task {
                await self?.consumeFrame(frame)
            }
        }

        try helper.start()
        captureSession = helper

        sessionState = CaptureSessionState(
            cameraID: cameraID,
            status: .capturing,
            lastErrorMessage: nil,
            lastFrameAt: nil,
            lastFrameSequence: nil,
            isActive: true,
            isReconnecting: false,
            restartCount: 0,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "AVFoundation Local Camera",
            usingVideoToolbox: nil,
            isUsingVideoToolboxFallback: false,
            processIdentifier: nil,
            diagnosticMessage: "AVFoundation camera session running"
        )

        AppLog.localCamera.info("Started local camera session for camera \(self.cameraID.uuidString, privacy: .public)")
    }

    func stop() async {
        captureSession?.stop()
        captureSession = nil
        await frameStore.reset()
        sessionState = CaptureSessionState.inactive(
            cameraID: cameraID,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "AVFoundation Local Camera"
        )
    }

    func latestFrame() async -> CapturedFrame? {
        await frameStore.current()
    }

    func state() async -> CaptureSessionState {
        sessionState
    }

    private func consumeFrame(_ frame: CapturedFrame) async {
        await frameStore.replace(with: frame)
        sessionState = CaptureSessionState(
            cameraID: cameraID,
            status: .capturing,
            lastErrorMessage: nil,
            lastFrameAt: frame.capturedAt,
            lastFrameSequence: frame.sourceFrameSequence,
            isActive: captureSession != nil,
            isReconnecting: false,
            restartCount: 0,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "AVFoundation Local Camera",
            usingVideoToolbox: nil,
            isUsingVideoToolboxFallback: false,
            processIdentifier: nil,
            diagnosticMessage: "Receiving local camera frames"
        )
    }
}

private enum LocalCameraStartError: LocalizedError {
    case permissionDenied
    case deviceUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission is required to capture frames from the local webcam."
        case .deviceUnavailable:
            return "The selected local camera is unavailable."
        }
    }
}

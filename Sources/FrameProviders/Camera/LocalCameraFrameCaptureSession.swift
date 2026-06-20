import Foundation

actor LocalCameraFrameCaptureSession: FrameProvider {
    nonisolated let id: UUID
    let configuration: CameraDefinition

    private let source: FrameSource
    private let deviceProvider: LocalCameraDeviceProvider
    private let frameStore = LatestCapturedFrameStore()
    private var captureSession: AVCaptureCameraSession?
    private var providerStatus: FrameProviderStatus

    init(source: FrameSource, deviceProvider: LocalCameraDeviceProvider) {
        self.id = source.camera.id
        self.configuration = source.camera
        self.source = source
        self.deviceProvider = deviceProvider
        self.providerStatus = FrameProviderStatus.inactive(
            sourceID: source.camera.id,
            providerType: .localCamera,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "AVFoundation Local Camera",
            state: .idle
        )
    }

    func start() async throws {
        guard captureSession == nil else { return }

        let status = await deviceProvider.authorizationStatus()
        if status != .authorized {
            if status == .notDetermined {
                let granted = await deviceProvider.requestAccess()
                guard granted else {
                    throw FrameProviderError.localCameraPermissionDenied
                }
            } else {
                throw FrameProviderError.localCameraPermissionDenied
            }
        }

        guard let deviceID = source.camera.trimmedLocalDeviceUniqueID else {
            throw FrameProviderError.localCameraUnavailable
        }

        guard await deviceProvider.deviceExists(uniqueID: deviceID) else {
            throw FrameProviderError.localCameraUnavailable
        }

        let helper = AVCaptureCameraSession(
            sourceID: source.camera.id,
            deviceUniqueID: deviceID,
            providerType: .localCamera,
            targetSize: CGSize(width: source.frameWidth, height: source.frameHeight)
        )

        helper.onFrame = { [weak self] frame in
            Task {
                await self?.consumeFrame(frame)
            }
        }

        try helper.start()
        captureSession = helper

        providerStatus = FrameProviderStatus(
            sourceID: id,
            providerType: .localCamera,
            state: .running,
            lastFrameAt: nil,
            lastFrameSequence: nil,
            lastError: nil,
            restartCount: 0,
            configuredFPS: source.configuredFPS,
            isActive: true,
            isReconnecting: false,
            sessionModeLabel: "AVFoundation Local Camera",
            usingVideoToolbox: nil,
            isUsingVideoToolboxFallback: false,
            processIdentifier: nil,
            diagnosticMessage: "AVFoundation camera session running",
            webViewNavigationStatus: nil,
            webViewWindowStatus: nil,
            screenCaptureStatus: nil,
            loadedURL: nil,
            windowTitle: nil,
            screenCapturePermissionDenied: false
        )

        AppLog.localCamera.info("Started local camera session for source \(self.id.uuidString, privacy: .public)")
    }

    func stop() async {
        captureSession?.stop()
        captureSession = nil
        await frameStore.reset()
        providerStatus = FrameProviderStatus.inactive(
            sourceID: id,
            providerType: .localCamera,
            configuredFPS: source.configuredFPS,
            sessionModeLabel: "AVFoundation Local Camera",
            state: .stopped
        )
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

    private func consumeFrame(_ frame: CapturedFrame) async {
        await frameStore.replace(with: frame)
        providerStatus = FrameProviderStatus(
            sourceID: id,
            providerType: .localCamera,
            state: .running,
            lastFrameAt: frame.capturedAt,
            lastFrameSequence: frame.sequence,
            lastError: nil,
            restartCount: 0,
            configuredFPS: source.configuredFPS,
            isActive: captureSession != nil,
            isReconnecting: false,
            sessionModeLabel: "AVFoundation Local Camera",
            usingVideoToolbox: nil,
            isUsingVideoToolboxFallback: false,
            processIdentifier: nil,
            diagnosticMessage: "Receiving local camera frames",
            webViewNavigationStatus: nil,
            webViewWindowStatus: nil,
            screenCaptureStatus: nil,
            loadedURL: nil,
            windowTitle: nil,
            screenCapturePermissionDenied: false
        )
    }
}

import Foundation

actor WebViewFrameProvider: FrameProvider {
    nonisolated let id: UUID
    let configuration: CameraDefinition

    private let windowManager: WebViewWindowManager
    private let screenCaptureSession: ScreenCaptureFrameSession
    private let configuredFPS: Double

    init(
        configuration: CameraDefinition,
        windowManager: WebViewWindowManager,
        configuredFPS: Double
    ) {
        self.id = configuration.id
        self.configuration = configuration
        self.windowManager = windowManager
        self.screenCaptureSession = ScreenCaptureFrameSession(sourceID: configuration.id)
        self.configuredFPS = configuredFPS
    }

    func start() async throws {
        guard configuration.hasValidWebViewURL else {
            throw FrameProviderError.invalidConfiguration("A valid HTTP or HTTPS WebView URL is required.")
        }

        let runtimeStatus = try await MainActor.run { () throws -> WebViewWindowRuntimeStatus in
            let controller = try windowManager.ensureWindow(for: configuration)
            controller.openWindow()
            return controller.statusSnapshot()
        }

        guard let windowID = runtimeStatus.windowID else {
            throw FrameProviderError.screenCaptureWindowUnavailable
        }

        try await screenCaptureSession.start(
            windowID: windowID,
            windowTitle: runtimeStatus.windowTitle,
            configuredFPS: configuredFPS,
            width: configuration.webViewWidth,
            height: configuration.webViewHeight
        )
    }

    func stop() async {
        await screenCaptureSession.stop()
    }

    func getSnapshot() async throws -> CapturedFrame {
        if let frame = await screenCaptureSession.latestFrame() {
            return frame
        }

        throw FrameProviderError.frameUnavailable
    }

    func latestFrame() async -> CapturedFrame? {
        await screenCaptureSession.latestFrame()
    }

    func getStatus() async -> FrameProviderStatus {
        let captureStatus = await screenCaptureSession.status(configuredFPS: configuredFPS)
        let windowStatus = await MainActor.run {
            windowManager.status(for: configuration.id)
        }

        return FrameProviderStatus(
            sourceID: configuration.id,
            providerType: .webView,
            state: captureStatus.isActive ? .running : .waitingForFrame,
            lastFrameAt: captureStatus.lastFrameAt,
            lastFrameSequence: captureStatus.lastFrameSequence,
            lastError: captureStatus.lastError ?? windowStatus?.lastError,
            restartCount: captureStatus.restartCount,
            configuredFPS: configuredFPS,
            isActive: captureStatus.isActive,
            isReconnecting: false,
            sessionModeLabel: "WKWebView + ScreenCaptureKit",
            usingVideoToolbox: nil,
            isUsingVideoToolboxFallback: false,
            processIdentifier: nil,
            diagnosticMessage: captureStatus.statusMessage,
            webViewNavigationStatus: windowStatus?.navigationStatus,
            webViewWindowStatus: windowStatus?.windowStatus,
            screenCaptureStatus: captureStatus.statusMessage,
            loadedURL: windowStatus?.loadedURL ?? configuration.trimmedStreamURL,
            windowTitle: windowStatus?.windowTitle ?? configuration.webViewWindowTitle,
            screenCapturePermissionDenied: captureStatus.screenCapturePermissionDenied
        )
    }
}

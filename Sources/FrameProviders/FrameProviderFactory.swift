import Foundation

struct FrameProviderFactory {
    typealias FFmpegBuilder = @Sendable (FrameSource, String) async throws -> any FrameProvider
    typealias WebViewBuilder = @Sendable (CameraDefinition, WebViewWindowManager, Double) async throws -> any FrameProvider
    typealias LocalCameraBuilder = @Sendable (FrameSource, LocalCameraDeviceProvider) async throws -> any FrameProvider

    let ffmpegLocator: FFmpegLocator
    let localCameraDeviceProvider: LocalCameraDeviceProvider
    let webViewWindowManager: WebViewWindowManager
    let ffmpegBuilder: FFmpegBuilder?
    let webViewBuilder: WebViewBuilder?
    let localCameraBuilder: LocalCameraBuilder?

    init(
        ffmpegLocator: FFmpegLocator,
        localCameraDeviceProvider: LocalCameraDeviceProvider,
        webViewWindowManager: WebViewWindowManager,
        ffmpegBuilder: FFmpegBuilder? = nil,
        webViewBuilder: WebViewBuilder? = nil,
        localCameraBuilder: LocalCameraBuilder? = nil
    ) {
        self.ffmpegLocator = ffmpegLocator
        self.localCameraDeviceProvider = localCameraDeviceProvider
        self.webViewWindowManager = webViewWindowManager
        self.ffmpegBuilder = ffmpegBuilder
        self.webViewBuilder = webViewBuilder
        self.localCameraBuilder = localCameraBuilder
    }

    func makeProvider(for source: FrameSource) async throws -> any FrameProvider {
        switch source.camera.providerType {
        case .ffmpeg:
            guard let ffmpegPath = ffmpegLocator.locate() else {
                throw FrameProviderError.ffmpegNotFound
            }

            if let ffmpegBuilder {
                return try await ffmpegBuilder(source, ffmpegPath)
            }

            return FFmpegPersistentFrameCaptureSession(source: source, ffmpegPath: ffmpegPath)
        case .webView:
            if let webViewBuilder {
                return try await webViewBuilder(source.camera, webViewWindowManager, source.configuredFPS)
            }

            return WebViewFrameProvider(
                configuration: source.camera,
                windowManager: webViewWindowManager,
                configuredFPS: source.configuredFPS
            )
        case .localCamera:
            if let localCameraBuilder {
                return try await localCameraBuilder(source, localCameraDeviceProvider)
            }

            return LocalCameraFrameCaptureSession(
                source: source,
                deviceProvider: localCameraDeviceProvider
            )
        }
    }
}

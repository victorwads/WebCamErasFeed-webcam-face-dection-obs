import CoreGraphics
import XCTest
@testable import CameraDirector

final class FrameProviderArchitectureTests: XCTestCase {
    func testFactoryUsesBuilderForEachProviderType() async throws {
        let tracker = TestInvocationTracker()
        let factory = await MainActor.run {
            FrameProviderFactory(
                ffmpegLocator: FFmpegLocator(),
                localCameraDeviceProvider: LocalCameraDeviceProvider(),
                webViewWindowManager: WebViewWindowManager(),
                ffmpegBuilder: { source, _ in
                    await tracker.record("ffmpeg:\(source.camera.id.uuidString)")
                    return MockFrameProvider(configuration: source.camera)
                },
                webViewBuilder: { configuration, _, _ in
                    await tracker.record("webview:\(configuration.id.uuidString)")
                    return MockFrameProvider(configuration: configuration)
                },
                localCameraBuilder: { source, _ in
                    await tracker.record("local:\(source.camera.id.uuidString)")
                    return MockFrameProvider(configuration: source.camera)
                }
            )
        }

        let ffmpegSource = FrameSource(camera: makeCamera(providerType: .ffmpeg), configuredFPS: 1, frameWidth: 640, frameHeight: 360)
        let webViewSource = FrameSource(camera: makeCamera(providerType: .webView), configuredFPS: 1, frameWidth: 640, frameHeight: 360)
        let localSource = FrameSource(camera: makeCamera(providerType: .localCamera), configuredFPS: 1, frameWidth: 640, frameHeight: 360)

        _ = try await factory.makeProvider(for: ffmpegSource)
        _ = try await factory.makeProvider(for: webViewSource)
        _ = try await factory.makeProvider(for: localSource)

        let calls = await tracker.values()
        XCTAssertEqual(calls.count, 3)
        XCTAssertTrue(calls.contains(where: { $0.hasPrefix("ffmpeg:") }))
        XCTAssertTrue(calls.contains(where: { $0.hasPrefix("webview:") }))
        XCTAssertTrue(calls.contains(where: { $0.hasPrefix("local:") }))
    }

    func testCoordinatorDoesNotDuplicateUnchangedProvidersAndRecreatesChangedProvider() async throws {
        let tracker = TestInvocationTracker()
        let factory = await MainActor.run {
            FrameProviderFactory(
                ffmpegLocator: FFmpegLocator(),
                localCameraDeviceProvider: LocalCameraDeviceProvider(),
                webViewWindowManager: WebViewWindowManager(),
                ffmpegBuilder: { source, _ in
                    await tracker.record("build:\(source.camera.id.uuidString):\(source.camera.trimmedStreamURL)")
                    return MockFrameProvider(configuration: source.camera)
                }
            )
        }

        let coordinator = FrameProviderCoordinator(providerFactory: factory)
        let sourceID = UUID()
        let initial = CameraDefinition(
            id: sourceID,
            name: "Cam",
            sceneName: "Scene",
            providerType: .ffmpeg,
            streamURL: "rtsp://127.0.0.1:8554/camera_a",
            isEnabled: true
        )

        await coordinator.apply(sources: [initial], captureInterval: 1.0)
        await coordinator.apply(sources: [initial], captureInterval: 1.0)

        var calls = await tracker.values()
        XCTAssertEqual(calls.count, 1)

        let modified = CameraDefinition(
            id: sourceID,
            name: "Cam",
            sceneName: "Scene",
            providerType: .ffmpeg,
            streamURL: "rtsp://127.0.0.1:8554/camera_b",
            isEnabled: true
        )

        await coordinator.apply(sources: [modified], captureInterval: 1.0)
        calls = await tracker.values()
        XCTAssertEqual(calls.count, 2)
    }

    func testSnapshotAllReturnsSuccessAndFailure() async throws {
        let goodCamera = makeCamera(providerType: .ffmpeg, streamURL: "rtsp://127.0.0.1:8554/camera_ok")
        let badCamera = makeCamera(providerType: .ffmpeg, streamURL: "rtsp://127.0.0.1:8554/camera_fail")
        let factory = await MainActor.run {
            FrameProviderFactory(
                ffmpegLocator: FFmpegLocator(),
                localCameraDeviceProvider: LocalCameraDeviceProvider(),
                webViewWindowManager: WebViewWindowManager(),
                ffmpegBuilder: { source, _ in
                    if source.camera.id == goodCamera.id {
                        return MockFrameProvider(configuration: source.camera, frame: try self.makeFrame(sourceID: source.camera.id, providerType: .ffmpeg, sequence: 1))
                    }
                    return MockFrameProvider(configuration: source.camera, snapshotError: FrameProviderError.frameUnavailable)
                }
            )
        }

        let coordinator = FrameProviderCoordinator(providerFactory: factory)
        await coordinator.apply(sources: [goodCamera, badCamera], captureInterval: 1.0)

        let results = await coordinator.snapshotAll()
        XCTAssertNotNil(try? results[goodCamera.id]?.get())
        XCTAssertThrowsError(try results[badCamera.id]?.get())
    }

    func testCameraDefinitionPersistsProviderType() throws {
        let camera = CameraDefinition(
            name: "WebView",
            sceneName: "Scene",
            providerType: .webView,
            streamURL: "http://127.0.0.1:1984/webrtc.html?src=camera_c300&media=video",
            webViewWidth: 1280,
            webViewHeight: 720,
            isEnabled: true
        )

        let data = try JSONEncoder().encode(camera)
        let decoded = try JSONDecoder().decode(CameraDefinition.self, from: data)
        XCTAssertEqual(decoded.providerType, .webView)
        XCTAssertEqual(decoded.webViewWidth, 1280)
        XCTAssertEqual(decoded.webViewHeight, 720)
    }

    func testFrameAnalysisSchedulerIgnoresProviderTypeAndUsesSequenceOnly() {
        let cameraID = UUID()
        let ffmpegFrame = CapturedFrame(
            sourceID: cameraID,
            providerType: .ffmpeg,
            image: makeSinglePixelImage(),
            capturedAt: Date(),
            sequence: 10,
            pixelSize: CGSize(width: 1, height: 1)
        )
        let webViewFrame = CapturedFrame(
            sourceID: cameraID,
            providerType: .webView,
            image: makeSinglePixelImage(),
            capturedAt: Date(),
            sequence: 11,
            pixelSize: CGSize(width: 1, height: 1)
        )

        XCTAssertFalse(
            FrameAnalysisScheduler.shouldAnalyze(
                cameraID: cameraID,
                frameSequence: ffmpegFrame.sequence,
                lastAnalyzedFrameSequenceByCamera: [cameraID: 10],
                inFlightCameraIDs: []
            )
        )

        XCTAssertTrue(
            FrameAnalysisScheduler.shouldAnalyze(
                cameraID: cameraID,
                frameSequence: webViewFrame.sequence,
                lastAnalyzedFrameSequenceByCamera: [cameraID: 10],
                inFlightCameraIDs: []
            )
        )
    }

    func testSelectionWorksAcrossThreeProviderTypes() async {
        let engine = CameraSelectionEngine(stabilityDuration: 0, switchCooldown: 0)
        let ffmpegID = UUID()
        let webViewID = UUID()
        let localCameraID = UUID()

        _ = await engine.evaluate(
            scores: [
                ffmpegID: CameraScore(faceCount: 1, largestFaceArea: 0.12, totalFaceArea: 0.12),
                webViewID: CameraScore(faceCount: 3, largestFaceArea: 0.08, totalFaceArea: 0.20),
                localCameraID: CameraScore(faceCount: 2, largestFaceArea: 0.18, totalFaceArea: 0.24)
            ],
            cameraOrder: [ffmpegID, webViewID, localCameraID],
            now: Date()
        )

        let outcome = await engine.evaluate(
            scores: [
                ffmpegID: CameraScore(faceCount: 1, largestFaceArea: 0.12, totalFaceArea: 0.12),
                webViewID: CameraScore(faceCount: 3, largestFaceArea: 0.08, totalFaceArea: 0.20),
                localCameraID: CameraScore(faceCount: 2, largestFaceArea: 0.18, totalFaceArea: 0.24)
            ],
            cameraOrder: [ffmpegID, webViewID, localCameraID]
        )

        XCTAssertEqual(outcome.selectedCameraID, webViewID)
    }

    private func makeCamera(
        providerType: FrameProviderType,
        streamURL: String = "rtsp://127.0.0.1:8554/camera_c300"
    ) -> CameraDefinition {
        CameraDefinition(
            name: "Camera",
            sceneName: "Scene",
            providerType: providerType,
            streamURL: providerType == .localCamera ? "" : streamURL,
            localDeviceUniqueID: providerType == .localCamera ? "mock-device" : nil,
            webViewWidth: 1280,
            webViewHeight: 720,
            isEnabled: true
        )
    }

    private func makeFrame(sourceID: UUID, providerType: FrameProviderType, sequence: UInt64) throws -> CapturedFrame {
        CapturedFrame(
            sourceID: sourceID,
            providerType: providerType,
            image: makeSinglePixelImage(),
            capturedAt: Date(),
            sequence: sequence,
            pixelSize: CGSize(width: 1, height: 1)
        )
    }

    private func makeSinglePixelImage() -> CGImage {
        let data = Data([0, 0, 0, 255])
        return try! BGRACGImageConverter.makeImage(from: data, width: 1, height: 1)
    }
}

private actor TestInvocationTracker {
    private var recordedValues: [String] = []

    func record(_ value: String) {
        recordedValues.append(value)
    }

    func values() -> [String] {
        recordedValues
    }
}

final actor MockFrameProvider: FrameProvider {
    nonisolated let id: UUID
    let configuration: CameraDefinition

    private let frame: CapturedFrame?
    private let snapshotError: Error?

    init(configuration: CameraDefinition, frame: CapturedFrame? = nil, snapshotError: Error? = nil) {
        self.id = configuration.id
        self.configuration = configuration
        self.frame = frame
        self.snapshotError = snapshotError
    }

    func start() async throws {}

    func stop() async {}

    func getSnapshot() async throws -> CapturedFrame {
        if let snapshotError {
            throw snapshotError
        }

        if let frame {
            return frame
        }

        throw FrameProviderError.frameUnavailable
    }

    func latestFrame() async -> CapturedFrame? {
        frame
    }

    func getStatus() async -> FrameProviderStatus {
        FrameProviderStatus(
            sourceID: id,
            providerType: configuration.providerType,
            state: frame == nil ? .waitingForFrame : .running,
            lastFrameAt: frame?.capturedAt,
            lastFrameSequence: frame?.sequence,
            lastError: snapshotError?.localizedDescription,
            restartCount: 0,
            configuredFPS: 1,
            isActive: true,
            isReconnecting: false,
            sessionModeLabel: "Mock",
            usingVideoToolbox: nil,
            isUsingVideoToolboxFallback: false,
            processIdentifier: nil,
            diagnosticMessage: "Mock",
            webViewNavigationStatus: nil,
            webViewWindowStatus: nil,
            screenCaptureStatus: nil,
            loadedURL: configuration.trimmedStreamURL,
            windowTitle: nil,
            screenCapturePermissionDenied: false
        )
    }
}

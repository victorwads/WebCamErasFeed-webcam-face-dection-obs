import XCTest
@testable import CameraDirector

final class FrameProviderCoordinatorPlanTests: XCTestCase {
    func testPlanKeepsUnchangedProvidersAndRestartsChangedOnes() {
        let id1 = UUID()
        let id2 = UUID()
        let old = [
            id1: makeSignature(id: id1, fps: 1),
            id2: makeSignature(id: id2, fps: 1)
        ]
        let desired = [
            id1: makeSignature(id: id1, fps: 1),
            id2: makeSignature(id: id2, fps: 2)
        ]

        let plan = FrameProviderCoordinator.makePlan(existing: old, desired: desired)

        XCTAssertEqual(plan.keep, [id1])
        XCTAssertEqual(plan.start, [id2])
        XCTAssertEqual(plan.stop, [id2])
    }

    private func makeSignature(id: UUID, fps: Double) -> CameraConfigurationSignature {
        CameraConfigurationSignature(
            id: id,
            providerType: .ffmpeg,
            streamURL: "rtsp://127.0.0.1:8554/camera_c300",
            localDeviceUniqueID: nil,
            isEnabled: true,
            captureFPS: fps,
            frameWidth: 640,
            frameHeight: 360,
            webViewWidth: 1280,
            webViewHeight: 720
        )
    }
}

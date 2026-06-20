import XCTest
@testable import CameraDirector

final class CameraSelectionEngineTests: XCTestCase {
    func testPrefersCameraWithMoreFaces() async {
        let engine = CameraSelectionEngine(stabilityDuration: 0, switchCooldown: 0)
        let cameraA = UUID()
        let cameraB = UUID()

        _ = await engine.evaluate(
            scores: [
                cameraA: CameraScore(faceCount: 1, largestFaceArea: 0.2, totalFaceArea: 0.2),
                cameraB: CameraScore(faceCount: 2, largestFaceArea: 0.1, totalFaceArea: 0.2)
            ],
            cameraOrder: [cameraA, cameraB],
            now: Date()
        )

        let outcome = await engine.evaluate(
            scores: [
                cameraA: CameraScore(faceCount: 1, largestFaceArea: 0.2, totalFaceArea: 0.2),
                cameraB: CameraScore(faceCount: 2, largestFaceArea: 0.1, totalFaceArea: 0.2)
            ],
            cameraOrder: [cameraA, cameraB]
        )

        XCTAssertEqual(outcome.selectedCameraID, cameraB)
    }
}

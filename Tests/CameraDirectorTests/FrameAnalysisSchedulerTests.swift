import XCTest
@testable import CameraDirector

final class FrameAnalysisSchedulerTests: XCTestCase {
    func testDoesNotAnalyzeSameFrameTwice() {
        let cameraID = UUID()

        XCTAssertFalse(
            FrameAnalysisScheduler.shouldAnalyze(
                cameraID: cameraID,
                frameSequence: 7,
                lastAnalyzedFrameSequenceByCamera: [cameraID: 7],
                inFlightCameraIDs: []
            )
        )
    }

    func testDoesNotAnalyzeWhileAlreadyInFlight() {
        let cameraID = UUID()

        XCTAssertFalse(
            FrameAnalysisScheduler.shouldAnalyze(
                cameraID: cameraID,
                frameSequence: 8,
                lastAnalyzedFrameSequenceByCamera: [:],
                inFlightCameraIDs: [cameraID]
            )
        )
    }

    func testAnalyzesNewFrameWhenIdle() {
        let cameraID = UUID()

        XCTAssertTrue(
            FrameAnalysisScheduler.shouldAnalyze(
                cameraID: cameraID,
                frameSequence: 9,
                lastAnalyzedFrameSequenceByCamera: [cameraID: 8],
                inFlightCameraIDs: []
            )
        )
    }
}

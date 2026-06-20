import XCTest
@testable import CameraDirector

final class CaptureRateCalculatorTests: XCTestCase {
    func testFramesPerSecondMatchesExpectedIntervals() {
        XCTAssertEqual(CaptureRateCalculator.framesPerSecond(for: 0.1), 10.0, accuracy: 0.001)
        XCTAssertEqual(CaptureRateCalculator.framesPerSecond(for: 0.5), 2.0, accuracy: 0.001)
        XCTAssertEqual(CaptureRateCalculator.framesPerSecond(for: 1.0), 1.0, accuracy: 0.001)
        XCTAssertEqual(CaptureRateCalculator.framesPerSecond(for: 5.0), 0.2, accuracy: 0.001)
        XCTAssertEqual(CaptureRateCalculator.framesPerSecond(for: 10.0), 0.1, accuracy: 0.001)
    }
}

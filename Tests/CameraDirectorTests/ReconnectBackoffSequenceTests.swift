import XCTest
@testable import CameraDirector

final class ReconnectBackoffSequenceTests: XCTestCase {
    func testBackoffGrowsAndCaps() {
        XCTAssertEqual(ReconnectBackoffSequence.delay(forAttempt: 1), 1)
        XCTAssertEqual(ReconnectBackoffSequence.delay(forAttempt: 2), 2)
        XCTAssertEqual(ReconnectBackoffSequence.delay(forAttempt: 3), 5)
        XCTAssertEqual(ReconnectBackoffSequence.delay(forAttempt: 4), 10)
        XCTAssertEqual(ReconnectBackoffSequence.delay(forAttempt: 10), 10)
    }
}

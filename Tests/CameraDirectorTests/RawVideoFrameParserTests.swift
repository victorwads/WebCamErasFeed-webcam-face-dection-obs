import XCTest
@testable import CameraDirector

final class RawVideoFrameParserTests: XCTestCase {
    func testAppendWithHalfFrameProducesNoFrame() {
        var parser = RawVideoFrameParser(frameSize: 8)
        let frames = parser.append(Data([1, 2, 3, 4]))

        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(parser.bufferedData, Data([1, 2, 3, 4]))
    }

    func testAppendWithOneAndHalfFramesKeepsRemainder() {
        var parser = RawVideoFrameParser(frameSize: 4)
        let frames = parser.append(Data([1, 2, 3, 4, 5, 6]))

        XCTAssertEqual(frames, [Data([1, 2, 3, 4])])
        XCTAssertEqual(parser.bufferedData, Data([5, 6]))
    }

    func testAppendWithMultipleFramesReturnsAllFrames() {
        var parser = RawVideoFrameParser(frameSize: 2)
        let frames = parser.append(Data([1, 2, 3, 4, 5, 6]))

        XCTAssertEqual(frames, [Data([1, 2]), Data([3, 4]), Data([5, 6])])
        XCTAssertTrue(parser.bufferedData.isEmpty)
    }

    func testAppendWithExactFrameSizeLeavesNoRemainder() {
        var parser = RawVideoFrameParser(frameSize: 3)
        let frames = parser.append(Data([7, 8, 9]))

        XCTAssertEqual(frames, [Data([7, 8, 9])])
        XCTAssertTrue(parser.bufferedData.isEmpty)
    }
}

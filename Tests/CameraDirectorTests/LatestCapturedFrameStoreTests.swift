import CoreGraphics
import XCTest
@testable import CameraDirector

final class LatestCapturedFrameStoreTests: XCTestCase {
    func testStoreKeepsOnlyLatestFrame() async throws {
        let store = LatestCapturedFrameStore()

        let firstFrame = try makeFrame(sequence: 1, value: 10)
        let secondFrame = try makeFrame(sequence: 2, value: 20)

        await store.replace(with: firstFrame)
        await store.replace(with: secondFrame)

        let current = await store.current()
        XCTAssertEqual(current?.sourceFrameSequence, 2)
    }

    private func makeFrame(sequence: UInt64, value: UInt8) throws -> CapturedFrame {
        let data = Data([value, value, value, 255])
        let image = try BGRACGImageConverter.makeImage(from: data, width: 1, height: 1)
        return CapturedFrame(
            image: image,
            capturedAt: Date(),
            sourceFrameSequence: sequence,
            pixelSize: CGSize(width: 1, height: 1)
        )
    }
}

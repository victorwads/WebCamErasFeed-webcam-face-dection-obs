import CoreGraphics
import Foundation

struct CapturedFrame: @unchecked Sendable {
    let image: CGImage
    let capturedAt: Date
    let sourceFrameSequence: UInt64
    let pixelSize: CGSize
}

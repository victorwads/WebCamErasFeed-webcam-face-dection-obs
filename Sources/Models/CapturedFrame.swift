import CoreGraphics
import Foundation

struct CapturedFrame: @unchecked Sendable {
    let sourceID: UUID
    let providerType: FrameProviderType
    let image: CGImage
    let capturedAt: Date
    let sequence: UInt64
    let pixelSize: CGSize

    var sourceFrameSequence: UInt64 {
        sequence
    }
}

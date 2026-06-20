import AVFoundation
import CoreImage
import Foundation
import ScreenCaptureKit

final class ScreenCaptureFrameOutput: NSObject, SCStreamOutput {
    private let ciContext = CIContext(options: nil)
    private let onImage: @Sendable (CGImage) -> Void

    init(onImage: @escaping @Sendable (CGImage) -> Void) {
        self.onImage = onImage
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        onImage(cgImage)
    }
}

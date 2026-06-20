import AppKit
import CoreGraphics
import ImageIO

struct DecodedFrame {
    let cgImage: CGImage
    let nsImage: NSImage
    let pixelSize: CGSize
}

enum RawFrameDecoder {
    static func decodeImageData(_ data: Data) throws -> DecodedFrame {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw FFmpegFrameCaptureError.invalidImageData
        }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        return DecodedFrame(cgImage: cgImage, nsImage: nsImage, pixelSize: size)
    }
}

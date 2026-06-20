import CoreGraphics
import Foundation

enum BGRACGImageConverter {
    static func makeImage(
        from data: Data,
        width: Int,
        height: Int
    ) throws -> CGImage {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)

        guard let provider = CGDataProvider(data: data as CFData) else {
            throw RawVideoFrameParserError.unableToCreateDataProvider
        }

        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw RawVideoFrameParserError.unableToCreateImage
        }

        return image
    }
}

enum RawVideoFrameParserError: LocalizedError {
    case unableToCreateDataProvider
    case unableToCreateImage

    var errorDescription: String? {
        switch self {
        case .unableToCreateDataProvider:
            return "Unable to create an image data provider for the raw frame."
        case .unableToCreateImage:
            return "Unable to convert the raw BGRA frame into a CGImage."
        }
    }
}

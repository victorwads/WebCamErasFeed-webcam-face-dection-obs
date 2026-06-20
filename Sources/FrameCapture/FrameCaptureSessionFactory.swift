import Foundation

struct FrameCaptureSessionFactory {
    let ffmpegLocator: FFmpegLocator
    let localCameraDeviceProvider: LocalCameraDeviceProvider

    func makeSession(for source: FrameSource) async throws -> any FrameCaptureSession {
        switch source.camera.sourceType {
        case .networkStream:
            guard let ffmpegPath = ffmpegLocator.locate() else {
                throw FFmpegCaptureBootstrapError.ffmpegNotFound
            }

            return FFmpegPersistentFrameCaptureSession(source: source, ffmpegPath: ffmpegPath)
        case .localCamera:
            return LocalCameraFrameCaptureSession(
                source: source,
                deviceProvider: localCameraDeviceProvider
            )
        }
    }
}

enum FFmpegCaptureBootstrapError: LocalizedError {
    case ffmpegNotFound

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg was not found. Install it with Homebrew or place it in a supported path."
        }
    }
}

import Foundation

actor FrameCaptureManager {
    private let locator: FFmpegLocator
    private var inFlightCaptures: Set<UUID> = []
    private var resolvedFFmpegPath: String?

    init(locator: FFmpegLocator = FFmpegLocator()) {
        self.locator = locator
    }

    func captureFrame(for camera: CameraDefinition) async throws -> DecodedFrame? {
        guard !inFlightCaptures.contains(camera.id) else {
            return nil
        }

        inFlightCaptures.insert(camera.id)
        defer { inFlightCaptures.remove(camera.id) }

        let ffmpegPath = try resolveFFmpegPath()
        let capture = FFmpegFrameCapture(ffmpegPath: ffmpegPath)
        return try await capture.captureFrame(for: camera)
    }

    func reset() {
        inFlightCaptures.removeAll()
    }

    private func resolveFFmpegPath() throws -> String {
        if let resolvedFFmpegPath {
            return resolvedFFmpegPath
        }

        guard let path = locator.locate() else {
            throw FFmpegFrameCaptureError.ffmpegNotFound
        }

        resolvedFFmpegPath = path
        return path
    }
}

import CoreGraphics
import Foundation

actor FaceDetectionManager {
    private let detector: FaceDetecting

    init(detector: FaceDetecting = VisionFaceDetector()) {
        self.detector = detector
    }

    func detectFaces(in image: CGImage) async throws -> FaceDetectionResult {
        try await detector.detectFaces(in: image)
    }
}

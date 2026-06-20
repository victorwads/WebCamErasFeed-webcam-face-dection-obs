import CoreGraphics
import Vision

struct VisionFaceDetector: FaceDetecting {
    func detectFaces(in image: CGImage) async throws -> FaceDetectionResult {
        try await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let faces = observations.map {
                FaceObservationData(
                    boundingBox: $0.boundingBox,
                    confidence: $0.confidence
                )
            }

            return FaceDetectionResult(faces: faces, processedAt: Date())
        }.value
    }
}

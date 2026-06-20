import CoreGraphics
import Foundation

protocol FaceDetecting: Sendable {
    func detectFaces(in image: CGImage) async throws -> FaceDetectionResult
}

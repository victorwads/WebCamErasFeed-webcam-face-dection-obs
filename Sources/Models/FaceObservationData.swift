import CoreGraphics
import Foundation

struct FaceObservationData: Identifiable, Sendable, Hashable {
    let id: UUID
    let boundingBox: CGRect
    let confidence: Float
    let normalizedArea: CGFloat

    init(id: UUID = UUID(), boundingBox: CGRect, confidence: Float) {
        self.id = id
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.normalizedArea = boundingBox.width * boundingBox.height
    }
}

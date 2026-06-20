import CoreGraphics
import Foundation

struct FaceDetectionResult: Sendable {
    let faces: [FaceObservationData]
    let processedAt: Date

    var faceCount: Int {
        faces.count
    }

    var largestFaceArea: CGFloat {
        faces.map(\.normalizedArea).max() ?? 0
    }

    var totalFaceArea: CGFloat {
        faces.reduce(0) { $0 + $1.normalizedArea }
    }
}

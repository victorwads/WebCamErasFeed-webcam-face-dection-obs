import CoreGraphics
import Foundation

struct CameraScore: Comparable, Sendable, Equatable {
    let faceCount: Int
    let largestFaceArea: CGFloat
    let totalFaceArea: CGFloat

    init(result: FaceDetectionResult) {
        self.faceCount = result.faceCount
        self.largestFaceArea = result.largestFaceArea
        self.totalFaceArea = result.totalFaceArea
    }

    var hasFaces: Bool {
        faceCount > 0
    }

    static func < (lhs: CameraScore, rhs: CameraScore) -> Bool {
        if lhs.faceCount != rhs.faceCount {
            return lhs.faceCount < rhs.faceCount
        }

        if lhs.largestFaceArea != rhs.largestFaceArea {
            return lhs.largestFaceArea < rhs.largestFaceArea
        }

        return lhs.totalFaceArea < rhs.totalFaceArea
    }

    var shortDescription: String {
        if faceCount == 0 {
            return "No faces"
        }

        return "\(faceCount) face\(faceCount == 1 ? "" : "s"), largest \(largestFaceArea.formattedArea)"
    }
}

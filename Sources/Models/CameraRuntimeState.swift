import AppKit
import Foundation

enum CaptureStatus: String, Sendable {
    case idle
    case capturing
    case processing
    case error
}

struct CameraRuntimeState: Identifiable {
    let id: UUID
    var image: NSImage?
    var imagePixelSize: CGSize?
    var status: CaptureStatus
    var detectionResult: FaceDetectionResult?
    var lastCapturedAt: Date?
    var errorMessage: String?
    var isSelected: Bool
    var selectionReason: String?

    init(
        id: UUID,
        image: NSImage? = nil,
        imagePixelSize: CGSize? = nil,
        status: CaptureStatus = .idle,
        detectionResult: FaceDetectionResult? = nil,
        lastCapturedAt: Date? = nil,
        errorMessage: String? = nil,
        isSelected: Bool = false,
        selectionReason: String? = nil
    ) {
        self.id = id
        self.image = image
        self.imagePixelSize = imagePixelSize
        self.status = status
        self.detectionResult = detectionResult
        self.lastCapturedAt = lastCapturedAt
        self.errorMessage = errorMessage
        self.isSelected = isSelected
        self.selectionReason = selectionReason
    }
}

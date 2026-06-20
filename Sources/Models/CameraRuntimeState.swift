import AppKit
import Foundation

enum CaptureStatus: String, Sendable {
    case idle
    case starting
    case capturing
    case processing
    case reconnecting
    case stopped
    case error
}

struct CameraRuntimeState: Identifiable {
    let id: UUID
    var image: NSImage?
    var imagePixelSize: CGSize?
    var status: CaptureStatus
    var detectionResult: FaceDetectionResult?
    var lastCapturedAt: Date?
    var lastFrameSequence: UInt64?
    var errorMessage: String?
    var isSelected: Bool
    var selectionReason: String?
    var sourceType: CameraSourceType
    var configuredFPS: Double?
    var sessionModeLabel: String?
    var isSessionActive: Bool
    var usingVideoToolbox: Bool?
    var isUsingVideoToolboxFallback: Bool
    var restartCount: Int
    var isReconnecting: Bool
    var lastFrameAgeDescription: String?
    var diagnosticMessage: String?
    var processIdentifier: Int32?

    init(
        id: UUID,
        image: NSImage? = nil,
        imagePixelSize: CGSize? = nil,
        status: CaptureStatus = .idle,
        detectionResult: FaceDetectionResult? = nil,
        lastCapturedAt: Date? = nil,
        lastFrameSequence: UInt64? = nil,
        errorMessage: String? = nil,
        isSelected: Bool = false,
        selectionReason: String? = nil,
        sourceType: CameraSourceType = .networkStream,
        configuredFPS: Double? = nil,
        sessionModeLabel: String? = nil,
        isSessionActive: Bool = false,
        usingVideoToolbox: Bool? = nil,
        isUsingVideoToolboxFallback: Bool = false,
        restartCount: Int = 0,
        isReconnecting: Bool = false,
        lastFrameAgeDescription: String? = nil,
        diagnosticMessage: String? = nil,
        processIdentifier: Int32? = nil
    ) {
        self.id = id
        self.image = image
        self.imagePixelSize = imagePixelSize
        self.status = status
        self.detectionResult = detectionResult
        self.lastCapturedAt = lastCapturedAt
        self.lastFrameSequence = lastFrameSequence
        self.errorMessage = errorMessage
        self.isSelected = isSelected
        self.selectionReason = selectionReason
        self.sourceType = sourceType
        self.configuredFPS = configuredFPS
        self.sessionModeLabel = sessionModeLabel
        self.isSessionActive = isSessionActive
        self.usingVideoToolbox = usingVideoToolbox
        self.isUsingVideoToolboxFallback = isUsingVideoToolboxFallback
        self.restartCount = restartCount
        self.isReconnecting = isReconnecting
        self.lastFrameAgeDescription = lastFrameAgeDescription
        self.diagnosticMessage = diagnosticMessage
        self.processIdentifier = processIdentifier
    }
}

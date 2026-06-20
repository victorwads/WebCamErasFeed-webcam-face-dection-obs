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
    var providerType: FrameProviderType
    var providerState: FrameProviderState?
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
    var webViewNavigationStatus: String?
    var webViewWindowStatus: String?
    var screenCaptureStatus: String?
    var loadedURL: String?
    var windowTitle: String?
    var screenCapturePermissionDenied: Bool

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
        providerType: FrameProviderType = .ffmpeg,
        providerState: FrameProviderState? = nil,
        configuredFPS: Double? = nil,
        sessionModeLabel: String? = nil,
        isSessionActive: Bool = false,
        usingVideoToolbox: Bool? = nil,
        isUsingVideoToolboxFallback: Bool = false,
        restartCount: Int = 0,
        isReconnecting: Bool = false,
        lastFrameAgeDescription: String? = nil,
        diagnosticMessage: String? = nil,
        processIdentifier: Int32? = nil,
        webViewNavigationStatus: String? = nil,
        webViewWindowStatus: String? = nil,
        screenCaptureStatus: String? = nil,
        loadedURL: String? = nil,
        windowTitle: String? = nil,
        screenCapturePermissionDenied: Bool = false
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
        self.providerType = providerType
        self.providerState = providerState
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
        self.webViewNavigationStatus = webViewNavigationStatus
        self.webViewWindowStatus = webViewWindowStatus
        self.screenCaptureStatus = screenCaptureStatus
        self.loadedURL = loadedURL
        self.windowTitle = windowTitle
        self.screenCapturePermissionDenied = screenCapturePermissionDenied
    }

    var sourceType: FrameProviderType {
        get { providerType }
        set { providerType = newValue }
    }
}

import Foundation

enum FrameProviderState: String, Codable, Sendable {
    case idle
    case starting
    case running
    case waitingForFrame
    case reconnecting
    case stopped
    case failed
}

struct FrameProviderStatus: Sendable {
    let sourceID: UUID
    let providerType: FrameProviderType
    let state: FrameProviderState
    let lastFrameAt: Date?
    let lastFrameSequence: UInt64?
    let lastError: String?
    let restartCount: Int
    let configuredFPS: Double
    let isActive: Bool
    let isReconnecting: Bool
    let sessionModeLabel: String
    let usingVideoToolbox: Bool?
    let isUsingVideoToolboxFallback: Bool
    let processIdentifier: Int32?
    let diagnosticMessage: String?
    let webViewNavigationStatus: String?
    let webViewWindowStatus: String?
    let screenCaptureStatus: String?
    let loadedURL: String?
    let windowTitle: String?
    let screenCapturePermissionDenied: Bool

    static func inactive(
        sourceID: UUID,
        providerType: FrameProviderType,
        configuredFPS: Double,
        sessionModeLabel: String,
        error: String? = nil,
        state: FrameProviderState = .stopped
    ) -> FrameProviderStatus {
        FrameProviderStatus(
            sourceID: sourceID,
            providerType: providerType,
            state: state,
            lastFrameAt: nil,
            lastFrameSequence: nil,
            lastError: error,
            restartCount: 0,
            configuredFPS: configuredFPS,
            isActive: false,
            isReconnecting: false,
            sessionModeLabel: sessionModeLabel,
            usingVideoToolbox: nil,
            isUsingVideoToolboxFallback: false,
            processIdentifier: nil,
            diagnosticMessage: error,
            webViewNavigationStatus: nil,
            webViewWindowStatus: nil,
            screenCaptureStatus: nil,
            loadedURL: nil,
            windowTitle: nil,
            screenCapturePermissionDenied: false
        )
    }
}

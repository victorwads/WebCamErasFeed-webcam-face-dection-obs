import Foundation

struct CaptureSessionState: Sendable {
    let cameraID: UUID
    let status: CaptureStatus
    let lastErrorMessage: String?
    let lastFrameAt: Date?
    let lastFrameSequence: UInt64?
    let isActive: Bool
    let isReconnecting: Bool
    let restartCount: Int
    let configuredFPS: Double
    let sessionModeLabel: String
    let usingVideoToolbox: Bool?
    let isUsingVideoToolboxFallback: Bool
    let processIdentifier: Int32?
    let diagnosticMessage: String?

    static func inactive(
        cameraID: UUID,
        configuredFPS: Double,
        sessionModeLabel: String,
        error: String? = nil,
        status: CaptureStatus = .stopped
    ) -> CaptureSessionState {
        CaptureSessionState(
            cameraID: cameraID,
            status: status,
            lastErrorMessage: error,
            lastFrameAt: nil,
            lastFrameSequence: nil,
            isActive: false,
            isReconnecting: false,
            restartCount: 0,
            configuredFPS: configuredFPS,
            sessionModeLabel: sessionModeLabel,
            usingVideoToolbox: nil,
            isUsingVideoToolboxFallback: false,
            processIdentifier: nil,
            diagnosticMessage: error
        )
    }
}

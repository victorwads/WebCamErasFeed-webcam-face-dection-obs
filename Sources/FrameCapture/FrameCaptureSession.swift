import Foundation

protocol FrameCaptureSession: Sendable {
    var cameraID: UUID { get }

    func start() async throws
    func stop() async
    func latestFrame() async -> CapturedFrame?
    func state() async -> CaptureSessionState
}

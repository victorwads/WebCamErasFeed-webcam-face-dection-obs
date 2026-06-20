import Foundation

protocol FrameProvider: Sendable {
    var id: UUID { get }
    var configuration: CameraDefinition { get }

    func start() async throws
    func stop() async
    func getSnapshot() async throws -> CapturedFrame
    func latestFrame() async -> CapturedFrame?
    func getStatus() async -> FrameProviderStatus
}

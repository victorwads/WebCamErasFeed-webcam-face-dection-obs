import Foundation

struct AppPreferences: Codable, Hashable, Sendable {
    var captureInterval: Double
    var isFaceDetectionEnabled: Bool
    var obsConfiguration: OBSConfiguration

    static let `default` = AppPreferences(
        captureInterval: 1.0,
        isFaceDetectionEnabled: true,
        obsConfiguration: .default
    )

    var clampedCaptureInterval: Double {
        min(max(captureInterval, 0.1), 10.0)
    }
}

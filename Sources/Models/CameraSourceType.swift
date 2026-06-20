import Foundation

enum CameraSourceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case networkStream
    case localCamera

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .networkStream:
            return "Network Stream"
        case .localCamera:
            return "Local Camera"
        }
    }
}

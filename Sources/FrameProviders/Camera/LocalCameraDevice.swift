import Foundation

struct LocalCameraDevice: Identifiable, Hashable, Sendable {
    let id: String
    let localizedName: String
}

enum LocalCameraAuthorizationStatus: String, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined

    var displayName: String {
        switch self {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        }
    }
}

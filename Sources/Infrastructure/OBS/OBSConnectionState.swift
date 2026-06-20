import Foundation

enum OBSConnectionState: String {
    case disconnected
    case connecting
    case connected
    case error

    var label: String {
        rawValue.capitalized
    }
}

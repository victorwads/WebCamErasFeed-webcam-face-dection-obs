import Foundation

enum ReconnectBackoffSequence {
    static func delay(forAttempt attempt: Int) -> TimeInterval {
        switch attempt {
        case ..<1:
            return 1
        case 1:
            return 1
        case 2:
            return 2
        case 3:
            return 5
        default:
            return 10
        }
    }
}

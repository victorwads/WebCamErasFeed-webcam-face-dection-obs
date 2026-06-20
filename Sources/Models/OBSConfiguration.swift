import Foundation

struct OBSConfiguration: Codable, Hashable, Sendable {
    var host: String
    var port: Int
    var password: String
    var isEnabled: Bool
    var automaticSceneSwitching: Bool

    static let `default` = OBSConfiguration(
        host: "127.0.0.1",
        port: 4455,
        password: "",
        isEnabled: false,
        automaticSceneSwitching: false
    )
}

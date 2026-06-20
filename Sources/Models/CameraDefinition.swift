import Foundation

struct CameraDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sceneName: String
    var streamURL: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        sceneName: String = "",
        streamURL: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sceneName = sceneName
        self.streamURL = streamURL
        self.isEnabled = isEnabled
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Camera" : name
    }

    var trimmedSceneName: String {
        sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedStreamURL: String {
        streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        streamURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasValidStreamURL: Bool {
        guard
            let url = URL(string: trimmedStreamURL),
            let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return scheme == "rtsp" && url.host != nil
    }
}

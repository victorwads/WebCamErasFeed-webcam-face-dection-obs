import Foundation

struct CameraDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sceneName: String
    var sourceType: CameraSourceType
    var streamURL: String
    var localDeviceUniqueID: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        sceneName: String = "",
        sourceType: CameraSourceType = .networkStream,
        streamURL: String = "",
        localDeviceUniqueID: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sceneName = sceneName
        self.sourceType = sourceType
        self.streamURL = streamURL
        self.localDeviceUniqueID = localDeviceUniqueID
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sceneName
        case sourceType
        case streamURL
        case localDeviceUniqueID
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sceneName = try container.decodeIfPresent(String.self, forKey: .sceneName) ?? ""
        sourceType = try container.decodeIfPresent(CameraSourceType.self, forKey: .sourceType) ?? .networkStream
        streamURL = try container.decodeIfPresent(String.self, forKey: .streamURL) ?? ""
        localDeviceUniqueID = try container.decodeIfPresent(String.self, forKey: .localDeviceUniqueID)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
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

    var trimmedLocalDeviceUniqueID: String? {
        let trimmed = localDeviceUniqueID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        streamURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (localDeviceUniqueID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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

    var hasValidLocalDeviceSelection: Bool {
        trimmedLocalDeviceUniqueID != nil
    }

    var isValidSourceConfiguration: Bool {
        switch sourceType {
        case .networkStream:
            return hasValidStreamURL
        case .localCamera:
            return hasValidLocalDeviceSelection
        }
    }

    var sourceSummary: String {
        switch sourceType {
        case .networkStream:
            return "RTSP"
        case .localCamera:
            return "Local Camera"
        }
    }

    func configurationSignature(
        captureFPS: Double,
        frameWidth: Int,
        frameHeight: Int
    ) -> CameraConfigurationSignature {
        CameraConfigurationSignature(
            id: id,
            sourceType: sourceType,
            streamURL: trimmedStreamURL,
            localDeviceUniqueID: trimmedLocalDeviceUniqueID,
            isEnabled: isEnabled,
            captureFPS: captureFPS,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
    }
}

struct CameraConfigurationSignature: Hashable, Sendable {
    let id: UUID
    let sourceType: CameraSourceType
    let streamURL: String
    let localDeviceUniqueID: String?
    let isEnabled: Bool
    let captureFPS: Double
    let frameWidth: Int
    let frameHeight: Int
}

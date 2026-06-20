import Foundation

struct CameraDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sceneName: String
    var providerType: FrameProviderType
    var streamURL: String
    var localDeviceUniqueID: String?
    var webViewWidth: Int
    var webViewHeight: Int
    var webViewWindowOriginX: Double?
    var webViewWindowOriginY: Double?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        sceneName: String = "",
        providerType: FrameProviderType = .ffmpeg,
        streamURL: String = "",
        localDeviceUniqueID: String? = nil,
        webViewWidth: Int = 1280,
        webViewHeight: Int = 720,
        webViewWindowOriginX: Double? = nil,
        webViewWindowOriginY: Double? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sceneName = sceneName
        self.providerType = providerType
        self.streamURL = streamURL
        self.localDeviceUniqueID = localDeviceUniqueID
        self.webViewWidth = max(320, webViewWidth)
        self.webViewHeight = max(180, webViewHeight)
        self.webViewWindowOriginX = webViewWindowOriginX
        self.webViewWindowOriginY = webViewWindowOriginY
        self.isEnabled = isEnabled
    }

    var sourceType: FrameProviderType {
        get { providerType }
        set { providerType = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sceneName
        case providerType
        case sourceType
        case streamURL
        case localDeviceUniqueID
        case webViewWidth
        case webViewHeight
        case webViewWindowOriginX
        case webViewWindowOriginY
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sceneName = try container.decodeIfPresent(String.self, forKey: .sceneName) ?? ""

        if let provider = try container.decodeIfPresent(FrameProviderType.self, forKey: .providerType) {
            providerType = provider
        } else {
            let legacyValue = try container.decodeIfPresent(String.self, forKey: .sourceType)
            providerType = FrameProviderType(legacyValue: legacyValue)
        }

        streamURL = try container.decodeIfPresent(String.self, forKey: .streamURL) ?? ""
        localDeviceUniqueID = try container.decodeIfPresent(String.self, forKey: .localDeviceUniqueID)
        webViewWidth = max(320, try container.decodeIfPresent(Int.self, forKey: .webViewWidth) ?? 1280)
        webViewHeight = max(180, try container.decodeIfPresent(Int.self, forKey: .webViewHeight) ?? 720)
        webViewWindowOriginX = try container.decodeIfPresent(Double.self, forKey: .webViewWindowOriginX)
        webViewWindowOriginY = try container.decodeIfPresent(Double.self, forKey: .webViewWindowOriginY)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sceneName, forKey: .sceneName)
        try container.encode(providerType, forKey: .providerType)
        try container.encode(streamURL, forKey: .streamURL)
        try container.encodeIfPresent(localDeviceUniqueID, forKey: .localDeviceUniqueID)
        try container.encode(webViewWidth, forKey: .webViewWidth)
        try container.encode(webViewHeight, forKey: .webViewHeight)
        try container.encodeIfPresent(webViewWindowOriginX, forKey: .webViewWindowOriginX)
        try container.encodeIfPresent(webViewWindowOriginY, forKey: .webViewWindowOriginY)
        try container.encode(isEnabled, forKey: .isEnabled)
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

    var hasValidRTSPURL: Bool {
        guard
            let url = URL(string: trimmedStreamURL),
            let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return scheme == "rtsp" && url.host != nil
    }

    var hasValidWebViewURL: Bool {
        guard
            let url = URL(string: trimmedStreamURL),
            let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    var hasValidLocalDeviceSelection: Bool {
        trimmedLocalDeviceUniqueID != nil
    }

    var isValidSourceConfiguration: Bool {
        switch providerType {
        case .ffmpeg:
            return hasValidRTSPURL
        case .webView:
            return hasValidWebViewURL
        case .localCamera:
            return hasValidLocalDeviceSelection
        }
    }

    var sourceSummary: String {
        providerType.displayName
    }

    var webViewWindowTitle: String {
        "WebCamErasFeed — \(displayName)"
    }

    func configurationSignature(
        captureFPS: Double,
        frameWidth: Int,
        frameHeight: Int
    ) -> CameraConfigurationSignature {
        CameraConfigurationSignature(
            id: id,
            providerType: providerType,
            streamURL: trimmedStreamURL,
            localDeviceUniqueID: trimmedLocalDeviceUniqueID,
            isEnabled: isEnabled,
            captureFPS: captureFPS,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            webViewWidth: webViewWidth,
            webViewHeight: webViewHeight
        )
    }
}

struct CameraConfigurationSignature: Hashable, Sendable {
    let id: UUID
    let providerType: FrameProviderType
    let streamURL: String
    let localDeviceUniqueID: String?
    let isEnabled: Bool
    let captureFPS: Double
    let frameWidth: Int
    let frameHeight: Int
    let webViewWidth: Int
    let webViewHeight: Int
}

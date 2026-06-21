import Foundation

struct OBSResolvedRTSPInputTemplate: Sendable, Equatable {
    let inputKind: String
    let templateSettings: [String: JSONValue]
}

actor OBSRTSPInputResolver {
    private weak var client: (any OBSProvisioningClient)?
    private let preferredExampleInputName: String

    init(
        client: any OBSProvisioningClient,
        preferredExampleInputName: String = "Example RTSP"
    ) {
        self.client = client
        self.preferredExampleInputName = preferredExampleInputName
    }

    func resolve() async throws -> OBSResolvedRTSPInputTemplate {
        guard let client else {
            throw ResolverError.clientUnavailable
        }

        let availableInputKinds = try await client.getInputKindList(unversioned: false)
        guard availableInputKinds.contains("ffmpeg_source") else {
            throw ResolverError.unsupportedRTSPInputKind(availableInputKinds: availableInputKinds)
        }

        let existingInputs = try await client.getInputList(inputKind: "ffmpeg_source")
        if let exampleInput = existingInputs.first(where: { $0.inputName == preferredExampleInputName }) {
            let settings = try await client.getInputSettings(inputName: exampleInput.inputName)
            return OBSResolvedRTSPInputTemplate(
                inputKind: exampleInput.inputKind,
                templateSettings: sanitizedTemplateSettings(from: settings.inputSettings)
            )
        }

        return OBSResolvedRTSPInputTemplate(
            inputKind: "ffmpeg_source",
            templateSettings: defaultTemplateSettings()
        )
    }

    private func sanitizedTemplateSettings(from settings: [String: JSONValue]) -> [String: JSONValue] {
        var sanitized = settings
        sanitized["is_local_file"] = .bool(false)
        sanitized.removeValue(forKey: "local_file")
        sanitized.removeValue(forKey: "playlist")
        sanitized.removeValue(forKey: "shutdown")
        return sanitized
    }

    private func defaultTemplateSettings() -> [String: JSONValue] {
        [
            "buffering_mb": .int(0),
            "clear_on_media_end": .bool(false),
            "close_when_inactive": .bool(false),
            "ffmpeg_options": .string("rtsp_transport=tcp"),
            "hw_decode": .bool(false),
            "is_local_file": .bool(false),
            "reconnect_delay_sec": .int(1),
            "restart_on_activate": .bool(false)
        ]
    }
}

extension OBSRTSPInputResolver {
    enum ResolverError: LocalizedError, Equatable {
        case clientUnavailable
        case unsupportedRTSPInputKind(availableInputKinds: [String])

        var errorDescription: String? {
            switch self {
            case .clientUnavailable:
                return "OBS provisioning client is unavailable."
            case .unsupportedRTSPInputKind(let availableInputKinds):
                let kinds = availableInputKinds.sorted().joined(separator: ", ")
                return "OBS does not expose the expected RTSP input kind. Available kinds: \(kinds)"
            }
        }
    }
}

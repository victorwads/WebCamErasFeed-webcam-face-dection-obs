import Foundation

actor OBSLocalCameraInputResolver {
    private weak var client: (any OBSProvisioningClient)?

    init(client: any OBSProvisioningClient) {
        self.client = client
    }

    func resolve() async throws -> OBSResolvedCameraInput {
        guard let client else {
            throw ResolverError.clientUnavailable
        }

        let availableKinds = try await client.getInputKindList(unversioned: false)
        let normalizedCandidates = [
            "av_capture_input_v2",
            "av_capture_input",
            "av_capture_input_v3"
        ]

        if let exact = normalizedCandidates.first(where: { availableKinds.contains($0) }) {
            let defaults = try await client.getInputDefaultSettings(inputKind: exact)
            return OBSResolvedCameraInput(inputKind: exact, defaultSettings: defaults)
        }

        if let fuzzy = availableKinds.first(where: { $0.localizedCaseInsensitiveContains("av_capture") }) {
            let defaults = try await client.getInputDefaultSettings(inputKind: fuzzy)
            return OBSResolvedCameraInput(inputKind: fuzzy, defaultSettings: defaults)
        }

        throw ResolverError.unsupportedInputKinds(availableKinds)
    }
}

extension OBSLocalCameraInputResolver {
    enum ResolverError: LocalizedError, Equatable {
        case clientUnavailable
        case unsupportedInputKinds([String])

        var errorDescription: String? {
            switch self {
            case .clientUnavailable:
                return "OBS provisioning client is unavailable."
            case .unsupportedInputKinds(let kinds):
                return "Could not identify a macOS camera input kind in OBS. Available kinds: \(kinds.joined(separator: ", "))"
            }
        }
    }
}

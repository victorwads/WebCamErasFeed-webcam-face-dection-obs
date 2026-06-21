import Foundation

actor OBSLocalCameraSceneProvisioner {
    private weak var client: (any OBSProvisioningClient)?
    private let inputResolver: OBSLocalCameraInputResolver

    init(client: any OBSProvisioningClient) {
        self.client = client
        self.inputResolver = OBSLocalCameraInputResolver(client: client)
    }

    func synchronize(sources: [CameraDefinition]) async -> OBSLocalCameraProvisioningReport {
        let managedSources = sources.filter { $0.isEnabled && $0.providerType == .localCamera }
        guard !managedSources.isEmpty else { return .empty }

        guard let client else {
            return OBSLocalCameraProvisioningReport(
                createdScenes: [],
                createdInputs: [],
                updatedInputs: [],
                unchangedInputs: [],
                errors: managedSources.map {
                    OBSLocalCameraProvisioningError(
                        sourceID: $0.id,
                        sourceName: $0.displayName,
                        message: "OBS provisioning client is unavailable."
                    )
                }
            )
        }

        guard await client.connectionState == .connected else {
            return OBSLocalCameraProvisioningReport(
                createdScenes: [],
                createdInputs: [],
                updatedInputs: [],
                unchangedInputs: [],
                errors: managedSources.map {
                    OBSLocalCameraProvisioningError(
                        sourceID: $0.id,
                        sourceName: $0.displayName,
                        message: "OBS is not connected."
                    )
                }
            )
        }

        do {
            let resolvedInput = try await inputResolver.resolve()
            let videoSettings = try await client.getVideoSettings()
            let desiredTransform = OBSSceneItemTransformSettings.fillCanvas(
                width: videoSettings.baseWidth,
                height: videoSettings.baseHeight
            )

            var sceneNames = Set(try await client.getSceneList().map(\.name))
            let existingInputs = try await client.getInputList(inputKind: nil)
            var inputSummariesByName = Dictionary(uniqueKeysWithValues: existingInputs.map { ($0.inputName, $0) })

            var createdScenes: [String] = []
            var createdInputs: [String] = []
            var updatedInputs: [String] = []
            var unchangedInputs: [String] = []
            var errors: [OBSLocalCameraProvisioningError] = []

            for source in managedSources {
                do {
                    let sceneName = OBSManagedNames.sceneName(for: source)
                    let inputName = OBSManagedNames.inputName(for: source)

                    if !sceneNames.contains(sceneName) {
                        try await client.createScene(named: sceneName)
                        sceneNames.insert(sceneName)
                        createdScenes.append(sceneName)
                    }

                    let desiredInputSettings = try await resolveInputSettings(
                        for: source,
                        resolvedInput: resolvedInput,
                        existingInputs: inputSummariesByName.values.sorted(by: { $0.inputName < $1.inputName }),
                        client: client
                    )

                    if inputSummariesByName[inputName] == nil {
                        try await client.createInput(
                            sceneName: sceneName,
                            inputName: inputName,
                            inputKind: resolvedInput.inputKind,
                            inputSettings: desiredInputSettings,
                            sceneItemEnabled: true
                        )
                        createdInputs.append(inputName)
                        inputSummariesByName[inputName] = OBSInputSummary(
                            id: inputName,
                            inputName: inputName,
                            inputKind: resolvedInput.inputKind,
                            unversionedInputKind: nil
                        )
                    } else {
                        let existing = try await client.getInputSettings(inputName: inputName)
                        if existing.inputSettings != desiredInputSettings {
                            try await client.setInputSettings(
                                inputName: inputName,
                                inputSettings: desiredInputSettings,
                                overlay: false
                            )
                            updatedInputs.append(inputName)
                        } else {
                            unchangedInputs.append(inputName)
                        }

                        if try await !sceneContainsInput(
                            sceneName: sceneName,
                            inputName: inputName,
                            client: client
                        ) {
                            _ = try await client.createSceneItem(
                                sceneName: sceneName,
                                sourceName: inputName,
                                sceneItemEnabled: true
                            )
                        }
                    }

                    let sceneItemId = try await client.getSceneItemId(sceneName: sceneName, sourceName: inputName)
                    let currentTransform = try await client.getSceneItemTransform(sceneName: sceneName, sceneItemId: sceneItemId)
                    if currentTransform != desiredTransform {
                        try await client.setSceneItemTransform(
                            sceneName: sceneName,
                            sceneItemId: sceneItemId,
                            transform: desiredTransform
                        )
                    }
                    try await client.setSceneItemLocked(sceneName: sceneName, sceneItemId: sceneItemId, locked: true)
                } catch {
                    errors.append(
                        OBSLocalCameraProvisioningError(
                            sourceID: source.id,
                            sourceName: source.displayName,
                            message: error.localizedDescription
                        )
                    )
                }
            }

            await client.refreshSceneList()

            return OBSLocalCameraProvisioningReport(
                createdScenes: createdScenes,
                createdInputs: createdInputs,
                updatedInputs: updatedInputs,
                unchangedInputs: unchangedInputs,
                errors: errors
            )
        } catch {
            return OBSLocalCameraProvisioningReport(
                createdScenes: [],
                createdInputs: [],
                updatedInputs: [],
                unchangedInputs: [],
                errors: managedSources.map {
                    OBSLocalCameraProvisioningError(
                        sourceID: $0.id,
                        sourceName: $0.displayName,
                        message: error.localizedDescription
                    )
                }
            )
        }
    }

    private func sceneContainsInput(
        sceneName: String,
        inputName: String,
        client: any OBSProvisioningClient
    ) async throws -> Bool {
        do {
            _ = try await client.getSceneItemId(sceneName: sceneName, sourceName: inputName)
            return true
        } catch {
            return false
        }
    }

    private func resolveInputSettings(
        for source: CameraDefinition,
        resolvedInput: OBSResolvedCameraInput,
        existingInputs: [OBSInputSummary],
        client: any OBSProvisioningClient
    ) async throws -> [String: JSONValue] {
        guard let uniqueID = source.trimmedLocalDeviceUniqueID else {
            throw ProvisionerError.invalidCameraConfiguration("No local camera identifier was selected.")
        }

        let candidateKeys = [
            "device",
            "uid",
            "device_id",
            "camera_id",
            "video_device_id",
            "capture_device",
            "unique_id"
        ]

        let existingSettings: [(String, [String: JSONValue])] = try await existingInputs
            .filter { summary in
                summary.inputKind == resolvedInput.inputKind || summary.unversionedInputKind == resolvedInput.inputKind
            }
            .asyncCompactMap { input in
                let result = try await client.getInputSettings(inputName: input.inputName)
                return (input.inputName, result.inputSettings)
            }

        for existingInput in existingInputs where existingInput.inputKind == resolvedInput.inputKind || existingInput.unversionedInputKind == resolvedInput.inputKind {
            for candidateKey in candidateKeys {
                if let items = try? await client.getInputPropertiesListPropertyItems(
                    inputName: existingInput.inputName,
                    propertyName: candidateKey
                ), items.contains(where: { $0.itemValue == uniqueID }) {
                    return [candidateKey: .string(uniqueID)]
                }
            }
        }

        if let matchedKey = candidateKeys.first(where: { key in
            existingSettings.contains(where: { $0.1[key]?.stringValue == uniqueID })
        }) {
            return [matchedKey: .string(uniqueID)]
        }

        if resolvedInput.inputKind == "av_capture_input_v2" {
            return ["device": .string(uniqueID)]
        }

        if let defaultKey = candidateKeys.first(where: { resolvedInput.defaultSettings[$0] != nil }) {
            return [defaultKey: .string(uniqueID)]
        }

        if let existingKey = candidateKeys.first(where: { key in
            existingSettings.contains(where: { $0.1[key] != nil })
        }) {
            return [existingKey: .string(uniqueID)]
        }

        let availableDefaultKeys = resolvedInput.defaultSettings.keys.sorted()
        let existingDiagnostic = existingSettings
            .map { name, settings in "\(name): \(settings)" }
            .joined(separator: " | ")

        throw ProvisionerError.deviceFieldResolutionFailed(
            inputKind: resolvedInput.inputKind,
            defaultSettings: availableDefaultKeys.joined(separator: ", "),
            existingSettings: existingDiagnostic,
            requestedDeviceIdentifier: uniqueID
        )
    }
}

private extension Array {
    func asyncCompactMap<T>(
        _ transform: (Element) async throws -> T?
    ) async throws -> [T] {
        var results: [T] = []
        for element in self {
            if let value = try await transform(element) {
                results.append(value)
            }
        }
        return results
    }
}

extension OBSLocalCameraSceneProvisioner {
    enum ProvisionerError: LocalizedError, Equatable {
        case invalidCameraConfiguration(String)
        case deviceFieldResolutionFailed(
            inputKind: String,
            defaultSettings: String,
            existingSettings: String,
            requestedDeviceIdentifier: String
        )

        var errorDescription: String? {
            switch self {
            case .invalidCameraConfiguration(let message):
                return message
            case .deviceFieldResolutionFailed(let inputKind, let defaultSettings, let existingSettings, let requestedDeviceIdentifier):
                return """
                Could not determine the OBS device settings field for local camera provisioning. \
                Input kind: \(inputKind). Default settings keys: \(defaultSettings). \
                Existing input settings: \(existingSettings.isEmpty ? "none" : existingSettings). \
                Requested device identifier: \(requestedDeviceIdentifier)
                """
            }
        }
    }
}

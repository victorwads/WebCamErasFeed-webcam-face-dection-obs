import Foundation

actor OBSRTSPSceneProvisioner {
    private weak var client: (any OBSProvisioningClient)?
    private let inputResolver: OBSRTSPInputResolver

    init(client: any OBSProvisioningClient) {
        self.client = client
        self.inputResolver = OBSRTSPInputResolver(client: client)
    }

    func synchronize(sources: [CameraDefinition]) async -> OBSProvisioningReport {
        let managedSources = sources.filter {
            $0.isEnabled && $0.providerType == .ffmpeg && $0.hasValidRTSPURL
        }
        guard !managedSources.isEmpty else { return .empty }

        guard let client else {
            return OBSProvisioningReport(
                createdScenes: [],
                createdInputs: [],
                updatedInputs: [],
                unchangedInputs: [],
                errors: managedSources.map {
                    OBSProvisioningError(
                        sourceID: $0.id,
                        sourceName: $0.displayName,
                        message: "OBS provisioning client is unavailable."
                    )
                }
            )
        }

        guard await client.connectionState == .connected else {
            return OBSProvisioningReport(
                createdScenes: [],
                createdInputs: [],
                updatedInputs: [],
                unchangedInputs: [],
                errors: managedSources.map {
                    OBSProvisioningError(
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
            var errors: [OBSProvisioningError] = []

            for source in managedSources {
                do {
                    let sceneName = OBSManagedNames.sceneName(for: source)
                    let inputName = OBSManagedNames.inputName(for: source)

                    if !sceneNames.contains(sceneName) {
                        try await client.createScene(named: sceneName)
                        sceneNames.insert(sceneName)
                        createdScenes.append(sceneName)
                    }

                    let desiredInputSettings = desiredSettings(
                        for: source,
                        template: resolvedInput.templateSettings
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
                        OBSProvisioningError(
                            sourceID: source.id,
                            sourceName: source.displayName,
                            message: error.localizedDescription
                        )
                    )
                }
            }

            await client.refreshSceneList()

            return OBSProvisioningReport(
                createdScenes: createdScenes,
                createdInputs: createdInputs,
                updatedInputs: updatedInputs,
                unchangedInputs: unchangedInputs,
                errors: errors
            )
        } catch {
            return OBSProvisioningReport(
                createdScenes: [],
                createdInputs: [],
                updatedInputs: [],
                unchangedInputs: [],
                errors: managedSources.map {
                    OBSProvisioningError(
                        sourceID: $0.id,
                        sourceName: $0.displayName,
                        message: error.localizedDescription
                    )
                }
            )
        }
    }

    private func desiredSettings(
        for source: CameraDefinition,
        template: [String: JSONValue]
    ) -> [String: JSONValue] {
        var settings = template
        settings["input"] = .string(source.trimmedStreamURL)
        settings["is_local_file"] = .bool(false)
        return settings
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
}

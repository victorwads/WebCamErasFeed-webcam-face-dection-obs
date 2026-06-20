import Foundation

actor FrameProviderCoordinator {
    private let providerFactory: FrameProviderFactory
    private let frameWidth: Int
    private let frameHeight: Int

    private var providers: [UUID: any FrameProvider] = [:]
    private var signatures: [UUID: CameraConfigurationSignature] = [:]
    private var inactiveStatuses: [UUID: FrameProviderStatus] = [:]

    init(
        providerFactory: FrameProviderFactory,
        frameWidth: Int = 640,
        frameHeight: Int = 360
    ) {
        self.providerFactory = providerFactory
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }

    func apply(
        sources: [CameraDefinition],
        captureInterval: TimeInterval
    ) async {
        let desiredFPS = CaptureRateCalculator.framesPerSecond(for: captureInterval)
        let enabledSources = sources.filter(\.isEnabled)
        let desiredSignatures = Dictionary(uniqueKeysWithValues: enabledSources.map {
            ($0.id, $0.configurationSignature(captureFPS: desiredFPS, frameWidth: frameWidth, frameHeight: frameHeight))
        })

        let plan = Self.makePlan(existing: signatures, desired: desiredSignatures)

        for id in Set(plan.stop) {
            if let provider = providers.removeValue(forKey: id) {
                await provider.stop()
            }
            signatures.removeValue(forKey: id)
        }

        for source in enabledSources where plan.start.contains(source.id) {
            let frameSource = FrameSource(
                camera: source,
                configuredFPS: desiredFPS,
                frameWidth: frameWidth,
                frameHeight: frameHeight
            )

            if let existing = providers.removeValue(forKey: source.id) {
                await existing.stop()
            }

            signatures[source.id] = frameSource.signature

            guard source.isValidSourceConfiguration else {
                inactiveStatuses[source.id] = invalidConfigurationStatus(for: source, fps: desiredFPS)
                continue
            }

            if source.providerType == .localCamera,
               let deviceID = source.trimmedLocalDeviceUniqueID,
               !(await providerFactory.localCameraDeviceProvider.deviceExists(uniqueID: deviceID)) {
                inactiveStatuses[source.id] = FrameProviderStatus.inactive(
                    sourceID: source.id,
                    providerType: .localCamera,
                    configuredFPS: desiredFPS,
                    sessionModeLabel: "AVFoundation Local Camera",
                    error: FrameProviderError.localCameraUnavailable.localizedDescription,
                    state: .failed
                )
                continue
            }

            do {
                let provider = try await providerFactory.makeProvider(for: frameSource)
                providers[source.id] = provider
                inactiveStatuses.removeValue(forKey: source.id)
                try await provider.start()
            } catch {
                inactiveStatuses[source.id] = FrameProviderStatus.inactive(
                    sourceID: source.id,
                    providerType: source.providerType,
                    configuredFPS: desiredFPS,
                    sessionModeLabel: source.providerType.displayName,
                    error: error.localizedDescription,
                    state: .failed
                )
            }
        }

        let disabledIDs = Set(sources.filter { !$0.isEnabled }.map(\.id))
        for id in disabledIDs {
            if let provider = providers.removeValue(forKey: id) {
                await provider.stop()
            }
            signatures.removeValue(forKey: id)
            if let source = sources.first(where: { $0.id == id }) {
                inactiveStatuses[id] = FrameProviderStatus.inactive(
                    sourceID: id,
                    providerType: source.providerType,
                    configuredFPS: desiredFPS,
                    sessionModeLabel: "Disabled",
                    state: .stopped
                )
            }
        }
    }

    func snapshot(for sourceID: UUID) async throws -> CapturedFrame {
        guard let provider = providers[sourceID] else {
            throw FrameProviderError.frameUnavailable
        }

        return try await provider.getSnapshot()
    }

    func latestFrame(for sourceID: UUID) async -> CapturedFrame? {
        guard let provider = providers[sourceID] else { return nil }
        return await provider.latestFrame()
    }

    func snapshotAll() async -> [UUID: Result<CapturedFrame, Error>] {
        let current = providers
        return await withTaskGroup(of: (UUID, Result<CapturedFrame, Error>).self) { group in
            for (id, provider) in current {
                group.addTask {
                    do {
                        return (id, .success(try await provider.getSnapshot()))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }

            var results: [UUID: Result<CapturedFrame, Error>] = [:]
            for await (id, result) in group {
                results[id] = result
            }
            return results
        }
    }

    func status(for sourceID: UUID) async -> FrameProviderStatus {
        if let provider = providers[sourceID] {
            return await provider.getStatus()
        }

        if let inactive = inactiveStatuses[sourceID] {
            return inactive
        }

        return FrameProviderStatus.inactive(
            sourceID: sourceID,
            providerType: .ffmpeg,
            configuredFPS: 0,
            sessionModeLabel: "Inactive"
        )
    }

    func stopAll() async {
        for provider in providers.values {
            await provider.stop()
        }
        providers.removeAll()
        signatures.removeAll()
    }

    private func invalidConfigurationStatus(
        for source: CameraDefinition,
        fps: Double
    ) -> FrameProviderStatus {
        let message: String
        switch source.providerType {
        case .ffmpeg:
            message = "A valid RTSP URL is required."
        case .webView:
            message = "A valid HTTP or HTTPS WebView URL is required."
        case .localCamera:
            message = "A local camera device must be selected."
        }

        return FrameProviderStatus.inactive(
            sourceID: source.id,
            providerType: source.providerType,
            configuredFPS: fps,
            sessionModeLabel: source.providerType.displayName,
            error: message,
            state: .failed
        )
    }

    static func makePlan(
        existing: [UUID: CameraConfigurationSignature],
        desired: [UUID: CameraConfigurationSignature]
    ) -> FrameProviderApplyPlan {
        let existingIDs = Set(existing.keys)
        let desiredIDs = Set(desired.keys)

        let removed = existingIDs.subtracting(desiredIDs)
        let added = desiredIDs.subtracting(existingIDs)
        let common = existingIDs.intersection(desiredIDs)

        let changed = common.filter { existing[$0] != desired[$0] }
        let kept = common.filter { existing[$0] == desired[$0] }

        return FrameProviderApplyPlan(
            start: Array(added.union(changed)).sorted(by: { $0.uuidString < $1.uuidString }),
            stop: Array(removed.union(changed)).sorted(by: { $0.uuidString < $1.uuidString }),
            keep: Array(kept).sorted(by: { $0.uuidString < $1.uuidString })
        )
    }
}

struct FrameProviderApplyPlan: Equatable {
    let start: [UUID]
    let stop: [UUID]
    let keep: [UUID]
}

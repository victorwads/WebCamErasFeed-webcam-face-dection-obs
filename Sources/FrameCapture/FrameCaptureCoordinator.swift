import Foundation

actor FrameCaptureCoordinator {
    private let sessionFactory: FrameCaptureSessionFactory
    private let frameWidth: Int
    private let frameHeight: Int

    private var sessions: [UUID: any FrameCaptureSession] = [:]
    private var signatures: [UUID: CameraConfigurationSignature] = [:]
    private var inactiveStates: [UUID: CaptureSessionState] = [:]

    init(
        sessionFactory: FrameCaptureSessionFactory,
        frameWidth: Int = 640,
        frameHeight: Int = 360
    ) {
        self.sessionFactory = sessionFactory
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }

    func apply(
        cameras: [CameraDefinition],
        captureInterval: TimeInterval
    ) async {
        let desiredFPS = CaptureRateCalculator.framesPerSecond(for: captureInterval)
        let enabledCameras = cameras.filter(\.isEnabled)
        let desiredSignatures = Dictionary(uniqueKeysWithValues: enabledCameras.map {
            ($0.id, $0.configurationSignature(captureFPS: desiredFPS, frameWidth: frameWidth, frameHeight: frameHeight))
        })

        let plan = Self.makePlan(
            existing: signatures,
            desired: desiredSignatures
        )

        let removedIDs = Set(plan.stop)
        for id in removedIDs {
            if let session = sessions.removeValue(forKey: id) {
                await session.stop()
            }
            signatures.removeValue(forKey: id)
        }

        for camera in enabledCameras where plan.start.contains(camera.id) {
            let source = FrameSource(
                camera: camera,
                configuredFPS: desiredFPS,
                frameWidth: frameWidth,
                frameHeight: frameHeight
            )
            let signature = source.signature

            if let existing = sessions.removeValue(forKey: camera.id) {
                await existing.stop()
            }

            signatures[camera.id] = signature

            guard camera.isValidSourceConfiguration else {
                inactiveStates[camera.id] = invalidConfigurationState(for: camera, fps: desiredFPS)
                continue
            }

            if camera.sourceType == .localCamera,
               let deviceID = camera.trimmedLocalDeviceUniqueID,
               !(await sessionFactory.localCameraDeviceProvider.deviceExists(uniqueID: deviceID)) {
                inactiveStates[camera.id] = CaptureSessionState.inactive(
                    cameraID: camera.id,
                    configuredFPS: desiredFPS,
                    sessionModeLabel: "AVFoundation Local Camera",
                    error: "The selected local camera is unavailable.",
                    status: .error
                )
                continue
            }

            do {
                let session = try await sessionFactory.makeSession(for: source)
                sessions[camera.id] = session
                inactiveStates.removeValue(forKey: camera.id)
                try await session.start()
            } catch {
                inactiveStates[camera.id] = CaptureSessionState.inactive(
                    cameraID: camera.id,
                    configuredFPS: desiredFPS,
                    sessionModeLabel: camera.sourceType == .networkStream ? "FFmpeg RTSP" : "AVFoundation Local Camera",
                    error: error.localizedDescription,
                    status: .error
                )
            }
        }

        let disabledIDs = Set(cameras.filter { !$0.isEnabled }.map(\.id))
        for id in disabledIDs {
            if let session = sessions.removeValue(forKey: id) {
                await session.stop()
            }
            signatures.removeValue(forKey: id)
            inactiveStates[id] = CaptureSessionState.inactive(
                cameraID: id,
                configuredFPS: desiredFPS,
                sessionModeLabel: "Disabled",
                status: .stopped
            )
        }
    }

    func latestFrame(for cameraID: UUID) async -> CapturedFrame? {
        guard let session = sessions[cameraID] else { return nil }
        return await session.latestFrame()
    }

    func state(for cameraID: UUID) async -> CaptureSessionState {
        if let session = sessions[cameraID] {
            return await session.state()
        }

        if let inactiveState = inactiveStates[cameraID] {
            return inactiveState
        }

        return CaptureSessionState.inactive(
            cameraID: cameraID,
            configuredFPS: 0,
            sessionModeLabel: "Inactive"
        )
    }

    func stopAll() async {
        for session in sessions.values {
            await session.stop()
        }
        sessions.removeAll()
        signatures.removeAll()
    }

    private func invalidConfigurationState(
        for camera: CameraDefinition,
        fps: Double
    ) -> CaptureSessionState {
        let message: String

        switch camera.sourceType {
        case .networkStream:
            message = "A valid RTSP URL is required."
        case .localCamera:
            message = "A local camera device must be selected."
        }

        return CaptureSessionState.inactive(
            cameraID: camera.id,
            configuredFPS: fps,
            sessionModeLabel: camera.sourceType == .networkStream ? "FFmpeg RTSP" : "AVFoundation Local Camera",
            error: message,
            status: .error
        )
    }

    static func makePlan(
        existing: [UUID: CameraConfigurationSignature],
        desired: [UUID: CameraConfigurationSignature]
    ) -> FrameCaptureApplyPlan {
        let existingIDs = Set(existing.keys)
        let desiredIDs = Set(desired.keys)

        let removed = existingIDs.subtracting(desiredIDs)
        let added = desiredIDs.subtracting(existingIDs)
        let common = existingIDs.intersection(desiredIDs)

        let changed = common.filter { existing[$0] != desired[$0] }
        let kept = common.filter { existing[$0] == desired[$0] }

        return FrameCaptureApplyPlan(
            start: Array(added.union(changed)).sorted(by: { $0.uuidString < $1.uuidString }),
            stop: Array(removed.union(changed)).sorted(by: { $0.uuidString < $1.uuidString }),
            keep: Array(kept).sorted(by: { $0.uuidString < $1.uuidString })
        )
    }
}

struct FrameCaptureApplyPlan: Equatable {
    let start: [UUID]
    let stop: [UUID]
    let keep: [UUID]
}

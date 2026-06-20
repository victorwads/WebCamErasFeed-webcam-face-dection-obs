import AppKit
import Foundation

@MainActor
final class MonitoringViewModel: ObservableObject {
    @Published private(set) var cameras: [CameraDefinition] = []
    @Published private(set) var runtimeStates: [UUID: CameraRuntimeState] = [:]
    @Published private(set) var selectionReason: String = "Apply settings to start monitoring."
    @Published private(set) var selectedCameraID: UUID?
    @Published private(set) var lastOBSSceneSwitchAt: Date?
    @Published private(set) var lastRequestedOBSSceneName: String?
    @Published private(set) var isMonitoring = false

    private let frameCaptureCoordinator: FrameCaptureCoordinator
    private let faceDetectionManager: FaceDetectionManager
    private let selectionEngine: CameraSelectionEngine
    private let obsClient: OBSClient
    private var preferences: AppPreferences = .default
    private var monitoringTask: Task<Void, Never>?
    private var lastAnalyzedFrameSequenceByCamera: [UUID: UInt64] = [:]
    private var inFlightAnalysisCameraIDs: Set<UUID> = []

    init(
        obsClient: OBSClient,
        localCameraDeviceProvider: LocalCameraDeviceProvider,
        faceDetectionManager: FaceDetectionManager = FaceDetectionManager(),
        selectionEngine: CameraSelectionEngine = CameraSelectionEngine()
    ) {
        self.obsClient = obsClient
        self.faceDetectionManager = faceDetectionManager
        self.selectionEngine = selectionEngine
        self.frameCaptureCoordinator = FrameCaptureCoordinator(
            sessionFactory: FrameCaptureSessionFactory(
                ffmpegLocator: FFmpegLocator(),
                localCameraDeviceProvider: localCameraDeviceProvider
            )
        )
    }

    func applyConfiguration(cameras: [CameraDefinition], preferences: AppPreferences) async {
        self.cameras = cameras
        self.preferences = preferences

        monitoringTask?.cancel()
        monitoringTask = nil
        await selectionEngine.reset()
        isMonitoring = false
        selectedCameraID = nil
        selectionReason = "Monitoring ready."
        rebuildRuntimeStates()
        lastAnalyzedFrameSequenceByCamera = [:]
        inFlightAnalysisCameraIDs = []

        await frameCaptureCoordinator.apply(
            cameras: cameras,
            captureInterval: preferences.clampedCaptureInterval
        )

        if preferences.obsConfiguration.isEnabled, obsClient.connectionState != .connected {
            await obsClient.connect(using: preferences.obsConfiguration)
        } else if !preferences.obsConfiguration.isEnabled, obsClient.connectionState != .disconnected {
            obsClient.disconnect()
        }

        guard !cameras.isEmpty else {
            selectionReason = "No cameras configured."
            return
        }

        monitoringTask = Task {
            await runMonitoringLoop()
        }
    }

    func orderedRuntimeStates() -> [(CameraDefinition, CameraRuntimeState)] {
        cameras
            .filter(\.isEnabled)
            .map { camera in
                (camera, runtimeStates[camera.id] ?? CameraRuntimeState(id: camera.id))
            }
    }

    func switchToScene(for camera: CameraDefinition) {
        Task {
            await obsClient.setCurrentProgramScene(sceneName: camera.trimmedSceneName)
            lastRequestedOBSSceneName = camera.trimmedSceneName
            lastOBSSceneSwitchAt = Date()
        }
    }

    private func runMonitoringLoop() async {
        isMonitoring = true

        while !Task.isCancelled {
            await performMonitoringCycle()

            let delay = UInt64(preferences.clampedCaptureInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }

        isMonitoring = false
    }

    private func performMonitoringCycle() async {
        let activeCameras = cameras.filter(\.isEnabled)
        let coordinator = frameCaptureCoordinator

        if activeCameras.isEmpty {
            selectionReason = "No enabled camera sources."
            clearTransientDetectionData()
            return
        }

        let snapshots = await withTaskGroup(of: CameraSnapshot.self) { group in
            for camera in activeCameras {
                group.addTask {
                    let frame = await coordinator.latestFrame(for: camera.id)
                    let state = await coordinator.state(for: camera.id)
                    return CameraSnapshot(
                        camera: camera,
                        frame: frame,
                        state: state
                    )
                }
            }

            var collected: [CameraSnapshot] = []
            for await snapshot in group {
                collected.append(snapshot)
            }
            return collected
        }

        for snapshot in snapshots {
            applySnapshot(snapshot, now: Date())
        }

        if !preferences.isFaceDetectionEnabled {
            selectedCameraID = nil
            selectionReason = "Face detection is disabled."
            clearDetectionSelections()
            return
        }

        let analysisResults = await analyzeNewFrames(from: snapshots)
        for result in analysisResults {
            applyAnalysisResult(result)
        }

        var scores: [UUID: CameraScore] = [:]
        for camera in activeCameras {
            if let result = runtimeStates[camera.id]?.detectionResult {
                scores[camera.id] = CameraScore(result: result)
            }
        }

        let selection = await selectionEngine.evaluate(
            scores: scores,
            cameraOrder: cameras.map(\.id)
        )

        selectedCameraID = selection.selectedCameraID
        selectionReason = selection.reason
        applySelectionState(selectedCameraID: selection.selectedCameraID, reason: selection.reason)

        guard selection.didSwitch, let selectedCameraID else { return }
        guard
            preferences.obsConfiguration.isEnabled,
            preferences.obsConfiguration.automaticSceneSwitching,
            obsClient.connectionState == .connected
        else {
            return
        }

        guard let selectedCamera = cameras.first(where: { $0.id == selectedCameraID }) else { return }
        guard selectedCamera.isEnabled, !selectedCamera.trimmedSceneName.isEmpty else { return }

        if obsClient.currentProgramSceneName == selectedCamera.trimmedSceneName {
            return
        }

        await obsClient.setCurrentProgramScene(sceneName: selectedCamera.trimmedSceneName)
        lastRequestedOBSSceneName = selectedCamera.trimmedSceneName
        lastOBSSceneSwitchAt = selection.lastSwitchAt
    }

    private func rebuildRuntimeStates() {
        let existing = runtimeStates
        runtimeStates = Dictionary(uniqueKeysWithValues: cameras.map { camera in
            var state = existing[camera.id] ?? CameraRuntimeState(id: camera.id)
            state.sourceType = camera.sourceType
            return (camera.id, state)
        })
    }

    private func clearTransientDetectionData() {
        for camera in cameras {
            runtimeStates[camera.id]?.detectionResult = nil
            runtimeStates[camera.id]?.isSelected = false
            runtimeStates[camera.id]?.selectionReason = nil
        }
    }

    private func clearDetectionSelections() {
        for camera in cameras {
            runtimeStates[camera.id]?.detectionResult = nil
            runtimeStates[camera.id]?.isSelected = false
            runtimeStates[camera.id]?.selectionReason = nil
        }
    }

    private func applySelectionState(selectedCameraID: UUID?, reason: String) {
        for camera in cameras {
            runtimeStates[camera.id]?.isSelected = camera.id == selectedCameraID
            runtimeStates[camera.id]?.selectionReason = camera.id == selectedCameraID ? reason : nil
        }
    }

    private func applySnapshot(_ snapshot: CameraSnapshot, now: Date) {
        var runtimeState = runtimeStates[snapshot.camera.id] ?? CameraRuntimeState(id: snapshot.camera.id)
        runtimeState.sourceType = snapshot.camera.sourceType
        runtimeState.status = snapshot.state.status
        runtimeState.errorMessage = snapshot.state.lastErrorMessage
        runtimeState.lastCapturedAt = snapshot.frame?.capturedAt ?? snapshot.state.lastFrameAt
        runtimeState.lastFrameSequence = snapshot.frame?.sourceFrameSequence ?? snapshot.state.lastFrameSequence
        runtimeState.imagePixelSize = snapshot.frame?.pixelSize
        runtimeState.configuredFPS = snapshot.state.configuredFPS
        runtimeState.sessionModeLabel = snapshot.state.sessionModeLabel
        runtimeState.isSessionActive = snapshot.state.isActive
        runtimeState.usingVideoToolbox = snapshot.state.usingVideoToolbox
        runtimeState.isUsingVideoToolboxFallback = snapshot.state.isUsingVideoToolboxFallback
        runtimeState.restartCount = snapshot.state.restartCount
        runtimeState.isReconnecting = snapshot.state.isReconnecting
        runtimeState.diagnosticMessage = snapshot.state.diagnosticMessage
        runtimeState.processIdentifier = snapshot.state.processIdentifier

        if let frame = snapshot.frame {
            runtimeState.image = NSImage(cgImage: frame.image, size: frame.pixelSize)
            runtimeState.lastFrameAgeDescription = now.timeIntervalSince(frame.capturedAt).formattedAge
        } else {
            runtimeState.lastFrameAgeDescription = nil
        }

        runtimeStates[snapshot.camera.id] = runtimeState
    }

    private func analyzeNewFrames(from snapshots: [CameraSnapshot]) async -> [AnalysisResult] {
        let faceDetectionManager = self.faceDetectionManager

        return await withTaskGroup(of: AnalysisResult?.self) { group in
            for snapshot in snapshots {
                guard let frame = snapshot.frame else { continue }
                guard FrameAnalysisScheduler.shouldAnalyze(
                    cameraID: snapshot.camera.id,
                    frameSequence: frame.sourceFrameSequence,
                    lastAnalyzedFrameSequenceByCamera: lastAnalyzedFrameSequenceByCamera,
                    inFlightCameraIDs: inFlightAnalysisCameraIDs
                ) else { continue }

                inFlightAnalysisCameraIDs.insert(snapshot.camera.id)
                runtimeStates[snapshot.camera.id]?.status = .processing

                group.addTask {
                    do {
                        let result = try await faceDetectionManager.detectFaces(in: frame.image)
                        return AnalysisResult(
                            cameraID: snapshot.camera.id,
                            frameSequence: frame.sourceFrameSequence,
                            detectionResult: result,
                            errorMessage: nil
                        )
                    } catch {
                        return AnalysisResult(
                            cameraID: snapshot.camera.id,
                            frameSequence: frame.sourceFrameSequence,
                            detectionResult: nil,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }

            var results: [AnalysisResult] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results
        }
    }

    private func applyAnalysisResult(_ result: AnalysisResult) {
        inFlightAnalysisCameraIDs.remove(result.cameraID)

        if let detectionResult = result.detectionResult {
            runtimeStates[result.cameraID]?.detectionResult = detectionResult
            runtimeStates[result.cameraID]?.status = .capturing
            runtimeStates[result.cameraID]?.errorMessage = nil
            lastAnalyzedFrameSequenceByCamera[result.cameraID] = result.frameSequence
        } else {
            runtimeStates[result.cameraID]?.status = .error
            runtimeStates[result.cameraID]?.errorMessage = result.errorMessage
        }
    }
}

private struct CameraSnapshot {
    let camera: CameraDefinition
    let frame: CapturedFrame?
    let state: CaptureSessionState
}

private struct AnalysisResult {
    let cameraID: UUID
    let frameSequence: UInt64
    let detectionResult: FaceDetectionResult?
    let errorMessage: String?
}

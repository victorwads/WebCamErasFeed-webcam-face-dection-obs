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

    private let frameProviderCoordinator: FrameProviderCoordinator
    private let faceDetectionManager: FaceDetectionManager
    private let selectionEngine: CameraSelectionEngine
    private let obsClient: OBSClient
    private var preferences: AppPreferences = .default
    private var monitoringTask: Task<Void, Never>?
    private var lastAnalyzedFrameSequenceByCamera: [UUID: UInt64] = [:]
    private var inFlightAnalysisCameraIDs: Set<UUID> = []

    init(
        obsClient: OBSClient,
        frameProviderCoordinator: FrameProviderCoordinator,
        faceDetectionManager: FaceDetectionManager = FaceDetectionManager(),
        selectionEngine: CameraSelectionEngine = CameraSelectionEngine()
    ) {
        self.obsClient = obsClient
        self.frameProviderCoordinator = frameProviderCoordinator
        self.faceDetectionManager = faceDetectionManager
        self.selectionEngine = selectionEngine
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

        await frameProviderCoordinator.apply(
            sources: cameras,
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
        let coordinator = frameProviderCoordinator

        if activeCameras.isEmpty {
            selectionReason = "No enabled camera sources."
            clearTransientDetectionData()
            return
        }

        let snapshots = await withTaskGroup(of: CameraSnapshot.self) { group in
            for camera in activeCameras {
                group.addTask {
                    let frame = await coordinator.latestFrame(for: camera.id)
                    let status = await coordinator.status(for: camera.id)
                    return CameraSnapshot(
                        camera: camera,
                        frame: frame,
                        status: status
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
            state.providerType = camera.providerType
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
        runtimeState.providerType = snapshot.camera.providerType
        runtimeState.providerState = snapshot.status.state
        runtimeState.status = snapshot.status.state.captureStatus
        runtimeState.errorMessage = snapshot.status.lastError
        runtimeState.lastCapturedAt = snapshot.frame?.capturedAt ?? snapshot.status.lastFrameAt
        runtimeState.lastFrameSequence = snapshot.frame?.sequence ?? snapshot.status.lastFrameSequence
        runtimeState.imagePixelSize = snapshot.frame?.pixelSize
        runtimeState.configuredFPS = snapshot.status.configuredFPS
        runtimeState.sessionModeLabel = snapshot.status.sessionModeLabel
        runtimeState.isSessionActive = snapshot.status.isActive
        runtimeState.usingVideoToolbox = snapshot.status.usingVideoToolbox
        runtimeState.isUsingVideoToolboxFallback = snapshot.status.isUsingVideoToolboxFallback
        runtimeState.restartCount = snapshot.status.restartCount
        runtimeState.isReconnecting = snapshot.status.isReconnecting
        runtimeState.diagnosticMessage = snapshot.status.diagnosticMessage
        runtimeState.processIdentifier = snapshot.status.processIdentifier
        runtimeState.webViewNavigationStatus = snapshot.status.webViewNavigationStatus
        runtimeState.webViewWindowStatus = snapshot.status.webViewWindowStatus
        runtimeState.screenCaptureStatus = snapshot.status.screenCaptureStatus
        runtimeState.loadedURL = snapshot.status.loadedURL
        runtimeState.windowTitle = snapshot.status.windowTitle
        runtimeState.screenCapturePermissionDenied = snapshot.status.screenCapturePermissionDenied

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
                    frameSequence: frame.sequence,
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
                            frameSequence: frame.sequence,
                            detectionResult: result,
                            errorMessage: nil
                        )
                    } catch {
                        return AnalysisResult(
                            cameraID: snapshot.camera.id,
                            frameSequence: frame.sequence,
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
    let status: FrameProviderStatus
}

private struct AnalysisResult {
    let cameraID: UUID
    let frameSequence: UInt64
    let detectionResult: FaceDetectionResult?
    let errorMessage: String?
}

private extension FrameProviderState {
    var captureStatus: CaptureStatus {
        switch self {
        case .idle:
            return .idle
        case .starting, .waitingForFrame:
            return .starting
        case .running:
            return .capturing
        case .reconnecting:
            return .reconnecting
        case .stopped:
            return .stopped
        case .failed:
            return .error
        }
    }
}

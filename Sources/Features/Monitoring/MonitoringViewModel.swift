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

    private let frameCaptureManager: FrameCaptureManager
    private let faceDetectionManager: FaceDetectionManager
    private let selectionEngine: CameraSelectionEngine
    private let obsClient: OBSClient
    private var preferences: AppPreferences = .default
    private var monitoringTask: Task<Void, Never>?

    init(
        obsClient: OBSClient,
        frameCaptureManager: FrameCaptureManager = FrameCaptureManager(),
        faceDetectionManager: FaceDetectionManager = FaceDetectionManager(),
        selectionEngine: CameraSelectionEngine = CameraSelectionEngine()
    ) {
        self.obsClient = obsClient
        self.frameCaptureManager = frameCaptureManager
        self.faceDetectionManager = faceDetectionManager
        self.selectionEngine = selectionEngine
    }

    func applyConfiguration(cameras: [CameraDefinition], preferences: AppPreferences) async {
        self.cameras = cameras
        self.preferences = preferences

        monitoringTask?.cancel()
        monitoringTask = nil
        await selectionEngine.reset()
        await frameCaptureManager.reset()
        isMonitoring = false
        selectedCameraID = nil
        selectionReason = "Monitoring ready."
        rebuildRuntimeStates()

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
        cameras.map { camera in
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
        let activeCameras = cameras.filter { $0.isEnabled && $0.hasValidStreamURL }

        if activeCameras.isEmpty {
            selectionReason = "No enabled cameras with valid RTSP URLs."
            clearTransientDetectionData()
            return
        }

        updateStatuses(for: activeCameras.map(\.id), status: .capturing, errorMessage: nil)

        let cycleResults = await withTaskGroup(of: CameraCycleResult.self) { group in
            for camera in activeCameras {
                let faceDetectionEnabled = preferences.isFaceDetectionEnabled
                group.addTask {
                    await Self.captureAndProcessCamera(
                        camera: camera,
                        frameCaptureManager: self.frameCaptureManager,
                        faceDetectionManager: self.faceDetectionManager,
                        faceDetectionEnabled: faceDetectionEnabled
                    )
                }
            }

            var collected: [CameraCycleResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        var scores: [UUID: CameraScore] = [:]

        for result in cycleResults {
            if preferences.isFaceDetectionEnabled, result.errorMessage == nil {
                runtimeStates[result.camera.id]?.status = .processing
            }

            var runtimeState = runtimeStates[result.camera.id] ?? CameraRuntimeState(id: result.camera.id)
            runtimeState.image = result.frame?.nsImage
            runtimeState.imagePixelSize = result.frame?.pixelSize
            runtimeState.lastCapturedAt = result.capturedAt
            runtimeState.errorMessage = result.errorMessage
            runtimeState.status = result.errorMessage == nil ? .idle : .error
            runtimeState.detectionResult = preferences.isFaceDetectionEnabled ? result.detectionResult : nil
            runtimeStates[result.camera.id] = runtimeState

            if let detectionResult = result.detectionResult {
                scores[result.camera.id] = CameraScore(result: detectionResult)
            }
        }

        if !preferences.isFaceDetectionEnabled {
            selectedCameraID = nil
            selectionReason = "Face detection is disabled."
            clearDetectionSelections()
            return
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
            let state = existing[camera.id] ?? CameraRuntimeState(id: camera.id)
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

    private func updateStatuses(for ids: [UUID], status: CaptureStatus, errorMessage: String?) {
        for id in ids {
            var state = runtimeStates[id] ?? CameraRuntimeState(id: id)
            state.status = status
            state.errorMessage = errorMessage
            runtimeStates[id] = state
        }
    }

    private static func captureAndProcessCamera(
        camera: CameraDefinition,
        frameCaptureManager: FrameCaptureManager,
        faceDetectionManager: FaceDetectionManager,
        faceDetectionEnabled: Bool
    ) async -> CameraCycleResult {
        do {
            guard let frame = try await frameCaptureManager.captureFrame(for: camera) else {
                return CameraCycleResult(camera: camera, frame: nil, detectionResult: nil, capturedAt: nil, errorMessage: nil)
            }

            let detectionResult: FaceDetectionResult?
            if faceDetectionEnabled {
                detectionResult = try await faceDetectionManager.detectFaces(in: frame.cgImage)
            } else {
                detectionResult = nil
            }

            return CameraCycleResult(
                camera: camera,
                frame: frame,
                detectionResult: detectionResult,
                capturedAt: Date(),
                errorMessage: nil
            )
        } catch {
            return CameraCycleResult(
                camera: camera,
                frame: nil,
                detectionResult: nil,
                capturedAt: nil,
                errorMessage: error.localizedDescription
            )
        }
    }
}

private struct CameraCycleResult {
    let camera: CameraDefinition
    let frame: DecodedFrame?
    let detectionResult: FaceDetectionResult?
    let capturedAt: Date?
    let errorMessage: String?
}

import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var cameras: [CameraDefinition]
    @Published var preferences: AppPreferences
    @Published var lastApplyMessage: String?

    var onApply: (@MainActor ([CameraDefinition], AppPreferences) async -> Void)?

    init(cameras: [CameraDefinition], preferences: AppPreferences) {
        self.cameras = cameras.isEmpty ? [CameraDefinition()] : cameras
        self.preferences = preferences
    }

    func addCamera() {
        cameras.append(CameraDefinition())
    }

    func removeCamera(id: UUID) {
        cameras.removeAll { $0.id == id }
        if cameras.isEmpty {
            cameras = [CameraDefinition()]
        }
    }

    func moveCameraUp(id: UUID) {
        guard let index = cameras.firstIndex(where: { $0.id == id }), index > 0 else { return }
        cameras.swapAt(index, index - 1)
    }

    func moveCameraDown(id: UUID) {
        guard let index = cameras.firstIndex(where: { $0.id == id }), index < cameras.count - 1 else { return }
        cameras.swapAt(index, index + 1)
    }

    func apply() async {
        preferences.captureInterval = preferences.clampedCaptureInterval
        let sanitizedCameras = sanitizedCameraDefinitions(from: cameras)
        await onApply?(sanitizedCameras, preferences)
        lastApplyMessage = "Settings applied at \(Date().formatted(date: .omitted, time: .standard))"
        replaceState(cameras: cameras, preferences: preferences)
    }

    func replaceState(cameras: [CameraDefinition], preferences: AppPreferences) {
        self.cameras = cameras.isEmpty ? [CameraDefinition()] : cameras
        self.preferences = preferences
    }

    private func sanitizedCameraDefinitions(from cameras: [CameraDefinition]) -> [CameraDefinition] {
        let trimmed = cameras.map { camera in
            CameraDefinition(
                id: camera.id,
                name: camera.name.trimmingCharacters(in: .whitespacesAndNewlines),
                sceneName: camera.sceneName.trimmingCharacters(in: .whitespacesAndNewlines),
                streamURL: camera.streamURL.trimmingCharacters(in: .whitespacesAndNewlines),
                isEnabled: camera.isEnabled
            )
        }

        return trimmed.filter { !$0.isEmpty }
    }
}

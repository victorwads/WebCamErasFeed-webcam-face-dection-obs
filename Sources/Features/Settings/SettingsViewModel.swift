import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var cameras: [CameraDefinition]
    @Published var preferences: AppPreferences
    @Published var lastApplyMessage: String?
    @Published private(set) var localCameraDevices: [LocalCameraDevice] = []
    @Published private(set) var localCameraAuthorizationStatus: LocalCameraAuthorizationStatus = .notDetermined
    @Published private(set) var webViewStatuses: [UUID: WebViewWindowRuntimeStatus] = [:]

    var onApply: (@MainActor ([CameraDefinition], AppPreferences) async -> Void)?
    private let localCameraDeviceProvider: LocalCameraDeviceProvider
    private let webViewWindowManager: WebViewWindowManager

    init(
        cameras: [CameraDefinition],
        preferences: AppPreferences,
        localCameraDeviceProvider: LocalCameraDeviceProvider,
        webViewWindowManager: WebViewWindowManager
    ) {
        self.cameras = cameras.isEmpty ? [CameraDefinition()] : cameras
        self.preferences = preferences
        self.localCameraDeviceProvider = localCameraDeviceProvider
        self.webViewWindowManager = webViewWindowManager
    }

    func addCamera() {
        cameras.append(CameraDefinition())
    }

    func removeCamera(id: UUID) {
        cameras.removeAll { $0.id == id }
        webViewStatuses.removeValue(forKey: id)
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

    func refreshLocalCameraDevices() async {
        localCameraAuthorizationStatus = await localCameraDeviceProvider.authorizationStatus()
        localCameraDevices = await localCameraDeviceProvider.listDevices()
    }

    func requestLocalCameraPermission() async {
        _ = await localCameraDeviceProvider.requestAccess()
        await refreshLocalCameraDevices()
    }

    func refreshWebViewStatus(for camera: CameraDefinition) {
        webViewStatuses[camera.id] = webViewWindowManager.status(for: camera.id)
    }

    func openWebViewWindow(for camera: CameraDefinition) {
        do {
            try webViewWindowManager.openWindow(for: camera)
        } catch {
            webViewStatuses[camera.id] = WebViewWindowRuntimeStatus(
                sourceID: camera.id,
                windowTitle: camera.webViewWindowTitle,
                loadedURL: camera.trimmedStreamURL,
                isWindowOpen: false,
                isVisible: false,
                isLoading: false,
                navigationStatus: "Failed",
                windowStatus: "Unavailable",
                lastError: error.localizedDescription,
                windowID: nil
            )
            return
        }

        refreshWebViewStatus(for: camera)
    }

    func reloadWebViewWindow(for camera: CameraDefinition) {
        do {
            try webViewWindowManager.reloadWindow(for: camera)
        } catch {
            webViewStatuses[camera.id] = WebViewWindowRuntimeStatus(
                sourceID: camera.id,
                windowTitle: camera.webViewWindowTitle,
                loadedURL: camera.trimmedStreamURL,
                isWindowOpen: false,
                isVisible: false,
                isLoading: false,
                navigationStatus: "Failed",
                windowStatus: "Unavailable",
                lastError: error.localizedDescription,
                windowID: nil
            )
            return
        }

        refreshWebViewStatus(for: camera)
    }

    func showWebViewWindow(for cameraID: UUID) {
        webViewWindowManager.showWindow(for: cameraID)
        if let camera = cameras.first(where: { $0.id == cameraID }) {
            refreshWebViewStatus(for: camera)
        }
    }

    func hideWebViewWindow(for cameraID: UUID) {
        webViewWindowManager.hideWindow(for: cameraID)
        if let camera = cameras.first(where: { $0.id == cameraID }) {
            refreshWebViewStatus(for: camera)
        }
    }

    func bringWebViewWindowToFront(for cameraID: UUID) {
        webViewWindowManager.bringWindowToFront(for: cameraID)
        if let camera = cameras.first(where: { $0.id == cameraID }) {
            refreshWebViewStatus(for: camera)
        }
    }

    func localCameraName(for uniqueID: String?) -> String? {
        guard let uniqueID else { return nil }
        return localCameraDevices.first(where: { $0.id == uniqueID })?.localizedName
    }

    private func sanitizedCameraDefinitions(from cameras: [CameraDefinition]) -> [CameraDefinition] {
        let trimmed = cameras.map { camera in
            CameraDefinition(
                id: camera.id,
                name: camera.name.trimmingCharacters(in: .whitespacesAndNewlines),
                sceneName: camera.sceneName.trimmingCharacters(in: .whitespacesAndNewlines),
                providerType: camera.providerType,
                streamURL: camera.streamURL.trimmingCharacters(in: .whitespacesAndNewlines),
                localDeviceUniqueID: camera.trimmedLocalDeviceUniqueID,
                webViewWidth: max(320, camera.webViewWidth),
                webViewHeight: max(180, camera.webViewHeight),
                webViewWindowOriginX: camera.webViewWindowOriginX,
                webViewWindowOriginY: camera.webViewWindowOriginY,
                isEnabled: camera.isEnabled
            )
        }

        return trimmed.filter { !$0.isEmpty }
    }
}

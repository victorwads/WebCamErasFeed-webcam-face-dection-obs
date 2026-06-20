import Foundation

@MainActor
final class AppState: ObservableObject {
    let settingsViewModel: SettingsViewModel
    let monitoringViewModel: MonitoringViewModel
    let obsClient: OBSClient

    private let preferencesStore: PreferencesStore
    private let cameraDefinitionsStore: CameraDefinitionsStore
    private let localCameraDeviceProvider: LocalCameraDeviceProvider

    init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        cameraDefinitionsStore: CameraDefinitionsStore = CameraDefinitionsStore()
    ) {
        let obsClient = OBSClient()
        let localCameraDeviceProvider = LocalCameraDeviceProvider()

        self.preferencesStore = preferencesStore
        self.cameraDefinitionsStore = cameraDefinitionsStore
        self.obsClient = obsClient
        self.localCameraDeviceProvider = localCameraDeviceProvider

        let storedPreferences = preferencesStore.load()
        let storedCameras = cameraDefinitionsStore.load()

        let settingsViewModel = SettingsViewModel(
            cameras: storedCameras,
            preferences: storedPreferences,
            localCameraDeviceProvider: localCameraDeviceProvider
        )
        let monitoringViewModel = MonitoringViewModel(
            obsClient: obsClient,
            localCameraDeviceProvider: localCameraDeviceProvider
        )

        self.settingsViewModel = settingsViewModel
        self.monitoringViewModel = monitoringViewModel

        settingsViewModel.onApply = { [weak self] cameras, preferences in
            await self?.apply(cameras: cameras, preferences: preferences)
        }

        Task {
            await apply(cameras: storedCameras, preferences: storedPreferences)
        }
    }

    func apply(cameras: [CameraDefinition], preferences: AppPreferences) async {
        cameraDefinitionsStore.save(cameras)
        preferencesStore.save(preferences)
        settingsViewModel.replaceState(cameras: cameras, preferences: preferences)
        await monitoringViewModel.applyConfiguration(cameras: cameras, preferences: preferences)
    }

    func connectOBS() {
        Task {
            await obsClient.connect(using: settingsViewModel.preferences.obsConfiguration)
        }
    }

    func disconnectOBS() {
        obsClient.disconnect()
    }

    func refreshOBSScenes() {
        Task {
            await obsClient.refreshSceneList()
        }
    }
}

import Foundation

@MainActor
final class AppState: ObservableObject {
    let settingsViewModel: SettingsViewModel
    let monitoringViewModel: MonitoringViewModel
    let obsClient: OBSClient

    private let preferencesStore: PreferencesStore
    private let cameraDefinitionsStore: CameraDefinitionsStore
    private let localCameraDeviceProvider: LocalCameraDeviceProvider
    @MainActor private let webViewWindowManager: WebViewWindowManager
    private let localCameraSceneProvisioner: OBSLocalCameraSceneProvisioner
    private let rtspSceneProvisioner: OBSRTSPSceneProvisioner

    init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        cameraDefinitionsStore: CameraDefinitionsStore = CameraDefinitionsStore()
    ) {
        let obsClient = OBSClient()
        let localCameraDeviceProvider = LocalCameraDeviceProvider()
        let webViewWindowManager = WebViewWindowManager()
        let frameProviderCoordinator = FrameProviderCoordinator(
            providerFactory: FrameProviderFactory(
                ffmpegLocator: FFmpegLocator(),
                localCameraDeviceProvider: localCameraDeviceProvider,
                webViewWindowManager: webViewWindowManager
            )
        )
        let localCameraSceneProvisioner = OBSLocalCameraSceneProvisioner(client: obsClient)
        let rtspSceneProvisioner = OBSRTSPSceneProvisioner(client: obsClient)

        self.preferencesStore = preferencesStore
        self.cameraDefinitionsStore = cameraDefinitionsStore
        self.obsClient = obsClient
        self.localCameraDeviceProvider = localCameraDeviceProvider
        self.webViewWindowManager = webViewWindowManager
        self.localCameraSceneProvisioner = localCameraSceneProvisioner
        self.rtspSceneProvisioner = rtspSceneProvisioner

        let storedPreferences = preferencesStore.load()
        let storedCameras = cameraDefinitionsStore.load()

        let settingsViewModel = SettingsViewModel(
            cameras: storedCameras,
            preferences: storedPreferences,
            localCameraDeviceProvider: localCameraDeviceProvider,
            webViewWindowManager: webViewWindowManager
        )
        let monitoringViewModel = MonitoringViewModel(
            obsClient: obsClient,
            frameProviderCoordinator: frameProviderCoordinator
        )

        self.settingsViewModel = settingsViewModel
        self.monitoringViewModel = monitoringViewModel

        settingsViewModel.onApply = { [weak self] cameras, preferences in
            await self?.apply(cameras: cameras, preferences: preferences) ?? "Settings applied."
        }
        settingsViewModel.onProvisionOBSScenes = { [weak self] cameras, preferences in
            await self?.provisionOBSScenes(cameras: cameras, preferences: preferences) ?? "OBS scenes synchronized."
        }

        if !ProcessInfo.processInfo.isRunningTests {
            Task {
                await apply(cameras: storedCameras, preferences: storedPreferences)
            }
        }
    }

    func apply(cameras: [CameraDefinition], preferences: AppPreferences) async -> String {
        cameraDefinitionsStore.save(cameras)
        preferencesStore.save(preferences)
        settingsViewModel.replaceState(cameras: cameras, preferences: preferences)
        await MainActor.run {
            webViewWindowManager.syncWindows(with: cameras)
        }
        await monitoringViewModel.applyConfiguration(cameras: cameras, preferences: preferences)

        guard preferences.obsConfiguration.isEnabled else {
            return "Settings applied. OBS integration is disabled."
        }

        let provisioningReport = await synchronizeOBSScenes(cameras: cameras)
        if provisioningReport.errors.isEmpty {
            return "Settings applied. \(provisioningReport.summaryText)"
        }

        let firstError = provisioningReport.errors.first?.message ?? "Unknown OBS provisioning error."
        return "Settings applied with OBS provisioning issues. \(provisioningReport.summaryText). First error: \(firstError)"
    }

    func connectOBS() {
        Task {
            await obsClient.connect(using: settingsViewModel.preferences.obsConfiguration)
        }
    }

    func provisionOBSScenes(cameras: [CameraDefinition], preferences: AppPreferences) async -> String {
        guard preferences.obsConfiguration.isEnabled else {
            return "OBS integration is disabled."
        }

        if obsClient.connectionState != .connected {
            await obsClient.connect(using: preferences.obsConfiguration)
        }

        guard obsClient.connectionState == .connected else {
            return obsClient.lastErrorMessage ?? "OBS is not connected."
        }

        let provisioningReport = await synchronizeOBSScenes(cameras: cameras)
        if provisioningReport.errors.isEmpty {
            return "OBS scenes synchronized. \(provisioningReport.summaryText)"
        }

        let firstError = provisioningReport.errors.first?.message ?? "Unknown OBS provisioning error."
        return "OBS scenes synchronized with issues. \(provisioningReport.summaryText). First error: \(firstError)"
    }

    func disconnectOBS() {
        obsClient.disconnect()
    }

    func refreshOBSScenes() {
        Task {
            await obsClient.refreshSceneList()
        }
    }

    private func synchronizeOBSScenes(cameras: [CameraDefinition]) async -> OBSProvisioningReport {
        let localReport = await localCameraSceneProvisioner.synchronize(sources: cameras)
        let rtspReport = await rtspSceneProvisioner.synchronize(sources: cameras)
        return localReport.merged(with: rtspReport)
    }
}

private extension ProcessInfo {
    var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}

import XCTest
@testable import CameraDirector

final class SettingsApplyTests: XCTestCase {
    @MainActor
    func testApplySettingsDoesNotRequireManualOBSSceneName() async {
        let viewModel = SettingsViewModel(
            cameras: [
                CameraDefinition(
                    name: "Local Camera",
                    sceneName: "",
                    providerType: .localCamera,
                    localDeviceUniqueID: "device-1",
                    isEnabled: true
                )
            ],
            preferences: .default,
            localCameraDeviceProvider: LocalCameraDeviceProvider(),
            webViewWindowManager: WebViewWindowManager()
        )

        var appliedCameras: [CameraDefinition] = []
        viewModel.onApply = { cameras, _ in
            appliedCameras = cameras
            return "Applied"
        }

        await viewModel.apply()

        XCTAssertEqual(appliedCameras.count, 1)
        XCTAssertEqual(appliedCameras.first?.sceneName, "")
        XCTAssertEqual(appliedCameras.first?.managedOBSSceneName, "[CameraDirector] Local Camera")
    }
}

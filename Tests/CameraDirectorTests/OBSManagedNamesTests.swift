import XCTest
@testable import CameraDirector

final class OBSManagedNamesTests: XCTestCase {
    func testSceneNameIsGeneratedFromVisibleCameraName() {
        let camera = CameraDefinition(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            name: "Desk Cam",
            providerType: .localCamera,
            localDeviceUniqueID: "device-1",
            isEnabled: true
        )

        XCTAssertEqual(OBSManagedNames.sceneName(for: camera), "[CameraDirector] Desk Cam")
        XCTAssertEqual(camera.managedOBSSceneName, "[CameraDirector] Desk Cam")
    }

    func testInputNameRemainsStableBasedOnUUID() {
        let camera = CameraDefinition(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            name: "First Name",
            providerType: .localCamera,
            localDeviceUniqueID: "device-1",
            isEnabled: true
        )

        let initial = OBSManagedNames.inputName(for: camera)
        var renamed = camera
        renamed.name = "Second Name"

        XCTAssertEqual(initial, OBSManagedNames.inputName(for: renamed))
        XCTAssertEqual(initial, "[CameraDirector] Camera - 00000000-0000-0000-0000-000000000456")
    }
}

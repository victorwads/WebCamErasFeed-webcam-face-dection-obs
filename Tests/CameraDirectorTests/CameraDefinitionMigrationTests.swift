import XCTest
@testable import CameraDirector

final class CameraDefinitionMigrationTests: XCTestCase {
    func testLegacyCameraDefinitionDefaultsToFFmpegProvider() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "sceneName": "Legacy Scene",
          "streamURL": "rtsp://127.0.0.1:8554/camera_c300",
          "isEnabled": true
        }
        """

        let camera = try JSONDecoder().decode(CameraDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(camera.providerType, .ffmpeg)
        XCTAssertNil(camera.localDeviceUniqueID)
    }
}

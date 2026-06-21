import XCTest
@testable import CameraDirector

@MainActor
final class OBSLocalCameraSceneProvisionerTests: XCTestCase {
    func testExistingSceneIsNotDuplicated() async {
        let camera = makeLocalCamera(name: "Desk Cam", deviceID: "device-1")
        let client = MockOBSProvisioningClient(
            scenes: [camera.managedOBSSceneName],
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["device_id": .string("")]]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [camera])

        XCTAssertTrue(report.createdScenes.isEmpty)
        XCTAssertEqual(client.createdSceneNames, [])
    }

    func testExistingInputIsNotDuplicated() async {
        let camera = makeLocalCamera(name: "Desk Cam", deviceID: "device-1")
        let inputName = camera.managedOBSInputName
        let sceneName = camera.managedOBSSceneName
        let client = MockOBSProvisioningClient(
            scenes: [sceneName],
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["device_id": .string("")]],
            inputs: [
                inputName: MockOBSProvisioningClient.InputState(
                    kind: "av_capture_input_v2",
                    settings: ["device_id": .string("device-1")]
                )
            ],
            sceneItems: [sceneName: [inputName: 10]]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [camera])

        XCTAssertTrue(report.createdInputs.isEmpty)
        XCTAssertEqual(report.unchangedInputs, [inputName])
        XCTAssertEqual(client.createdInputs.count, 0)
    }

    func testIncorrectExistingInputIsUpdated() async {
        let camera = makeLocalCamera(name: "Desk Cam", deviceID: "device-1")
        let inputName = camera.managedOBSInputName
        let sceneName = camera.managedOBSSceneName
        let client = MockOBSProvisioningClient(
            scenes: [sceneName],
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["device_id": .string("")]],
            inputs: [
                inputName: MockOBSProvisioningClient.InputState(
                    kind: "av_capture_input_v2",
                    settings: ["device_id": .string("wrong-device")]
                )
            ],
            sceneItems: [sceneName: [inputName: 20]]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [camera])

        XCTAssertEqual(report.updatedInputs, [inputName])
        XCTAssertEqual(client.inputs[inputName]?.settings["device"], .string("device-1"))
    }

    func testExistingInputIsAttachedToSceneWhenMissingSceneItem() async {
        let camera = makeLocalCamera(name: "Desk Cam", deviceID: "device-1")
        let inputName = camera.managedOBSInputName
        let sceneName = camera.managedOBSSceneName
        let client = MockOBSProvisioningClient(
            scenes: [sceneName],
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["device_id": .string("")]],
            inputs: [
                inputName: MockOBSProvisioningClient.InputState(
                    kind: "av_capture_input_v2",
                    settings: ["device_id": .string("device-1")]
                )
            ],
            sceneItems: [:]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [camera])

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(client.createdSceneItems, [MockOBSProvisioningClient.CreatedSceneItemCall(sceneName: sceneName, sourceName: inputName)])
        XCTAssertNotNil(client.sceneItems[sceneName]?[inputName])
    }

    func testCorrectDeviceIdentifierIsAppliedToInputSettings() async {
        let camera = makeLocalCamera(name: "Cam", deviceID: "persistent-device-id")
        let client = MockOBSProvisioningClient(
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["device_id": .string("")]]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        _ = await provisioner.synchronize(sources: [camera])

        let created = client.createdInputs.first
        XCTAssertEqual(created?.inputSettings["device"], .string("persistent-device-id"))
    }

    func testUsesUIDWhenOBSDefaultsExposeUIDField() async {
        let camera = makeLocalCamera(name: "MacCam", deviceID: "camera-uid")
        let client = MockOBSProvisioningClient(
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["uid": .string("")]]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        _ = await provisioner.synchronize(sources: [camera])

        let created = client.createdInputs.first
        XCTAssertEqual(created?.inputSettings["device"], .string("camera-uid"))
    }

    func testUsesPropertyListDeviceFieldWhenAvailable() async {
        let camera = makeLocalCamera(name: "MacCam", deviceID: "camera-uid")
        let existingInput = "Existing Camera"
        let client = MockOBSProvisioningClient(
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["uid": .string("")]],
            inputs: [
                existingInput: MockOBSProvisioningClient.InputState(
                    kind: "av_capture_input_v2",
                    settings: [:]
                )
            ],
            propertyItemsByInputAndProperty: [
                existingInput: [
                    "device": [
                        OBSPropertyListItem(itemName: "Camera", itemValue: "camera-uid", itemEnabled: true)
                    ]
                ]
            ]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        _ = await provisioner.synchronize(sources: [camera])

        let created = client.createdInputs.first
        XCTAssertEqual(created?.inputSettings["device"], .string("camera-uid"))
    }

    func testTransformUsesOBSCanvasDimensions() async {
        let camera = makeLocalCamera(name: "Cam", deviceID: "device-1")
        let inputName = camera.managedOBSInputName
        let sceneName = camera.managedOBSSceneName
        let client = MockOBSProvisioningClient(
            scenes: [sceneName],
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["device_id": .string("")]],
            inputs: [
                inputName: MockOBSProvisioningClient.InputState(
                    kind: "av_capture_input_v2",
                    settings: ["device_id": .string("device-1")]
                )
            ],
            sceneItems: [sceneName: [inputName: 30]],
            videoSettings: OBSVideoSettings(baseWidth: 2560, baseHeight: 1440)
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        _ = await provisioner.synchronize(sources: [camera])

        XCTAssertEqual(client.lastTransformBySceneItemID[30]?.positionX, 1280)
        XCTAssertEqual(client.lastTransformBySceneItemID[30]?.positionY, 720)
        XCTAssertEqual(client.lastTransformBySceneItemID[30]?.alignment, 0)
        XCTAssertEqual(client.lastTransformBySceneItemID[30]?.boundsAlignment, 0)
        XCTAssertEqual(client.lastTransformBySceneItemID[30]?.boundsWidth, 2560)
        XCTAssertEqual(client.lastTransformBySceneItemID[30]?.boundsHeight, 1440)
        XCTAssertEqual(client.lastTransformBySceneItemID[30]?.boundsType, "OBS_BOUNDS_SCALE_INNER")
    }

    func testErrorInOneCameraDoesNotInterruptOthers() async {
        let good = makeLocalCamera(name: "Good", deviceID: "device-1")
        let bad = makeLocalCamera(name: "Bad", deviceID: "device-2")
        let client = MockOBSProvisioningClient(
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["device_id": .string("")]],
            failingCreateInputNames: [bad.managedOBSInputName]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [good, bad])

        XCTAssertEqual(report.createdInputs, [good.managedOBSInputName])
        XCTAssertEqual(report.errors.count, 1)
        XCTAssertEqual(report.errors.first?.sourceID, bad.id)
    }

    func testWebViewAndFFmpegSourcesAreIgnored() async {
        let ffmpeg = CameraDefinition(name: "RTSP", providerType: .ffmpeg, streamURL: "rtsp://127.0.0.1/stream", isEnabled: true)
        let webView = CameraDefinition(name: "Web", providerType: .webView, streamURL: "http://127.0.0.1:1984/webrtc.html?src=a&media=video", isEnabled: true)
        let client = MockOBSProvisioningClient(
            inputKinds: ["av_capture_input_v2"],
            defaultSettingsByKind: ["av_capture_input_v2": ["device_id": .string("")]]
        )
        let provisioner = OBSLocalCameraSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [ffmpeg, webView])

        XCTAssertEqual(report, .empty)
        XCTAssertTrue(client.createdSceneNames.isEmpty)
        XCTAssertTrue(client.createdInputs.isEmpty)
    }

    func testExistingRTSPInputIsNotDuplicated() async {
        let source = makeRTSPCamera(name: "Kitchen", streamURL: "rtsp://127.0.0.1:8554/camera_kitchen")
        let inputName = source.managedOBSInputName
        let sceneName = source.managedOBSSceneName
        let client = MockOBSProvisioningClient(
            scenes: [sceneName],
            inputKinds: ["ffmpeg_source"],
            defaultSettingsByKind: ["ffmpeg_source": [:]],
            inputs: [
                "Example RTSP": MockOBSProvisioningClient.InputState(
                    kind: "ffmpeg_source",
                    settings: [
                        "buffering_mb": .int(0),
                        "clear_on_media_end": .bool(false),
                        "close_when_inactive": .bool(false),
                        "ffmpeg_options": .string("rtsp_transport=tcp"),
                        "hw_decode": .bool(false),
                        "input": .string("rtsp://localhost:8554/example"),
                        "is_local_file": .bool(false),
                        "reconnect_delay_sec": .int(1),
                        "restart_on_activate": .bool(false)
                    ]
                ),
                inputName: MockOBSProvisioningClient.InputState(
                    kind: "ffmpeg_source",
                    settings: [
                        "buffering_mb": .int(0),
                        "clear_on_media_end": .bool(false),
                        "close_when_inactive": .bool(false),
                        "ffmpeg_options": .string("rtsp_transport=tcp"),
                        "hw_decode": .bool(false),
                        "input": .string("rtsp://127.0.0.1:8554/camera_kitchen"),
                        "is_local_file": .bool(false),
                        "reconnect_delay_sec": .int(1),
                        "restart_on_activate": .bool(false)
                    ]
                )
            ],
            sceneItems: [sceneName: [inputName: 44]]
        )
        let provisioner = OBSRTSPSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [source])

        XCTAssertTrue(report.createdInputs.isEmpty)
        XCTAssertEqual(report.unchangedInputs, [inputName])
    }

    func testRTSPInputUsesExampleTemplateAndCurrentURL() async {
        let source = makeRTSPCamera(name: "Kitchen", streamURL: "rtsp://127.0.0.1:8554/camera_kitchen")
        let client = MockOBSProvisioningClient(
            inputKinds: ["ffmpeg_source"],
            defaultSettingsByKind: ["ffmpeg_source": [:]],
            inputs: [
                "Example RTSP": MockOBSProvisioningClient.InputState(
                    kind: "ffmpeg_source",
                    settings: [
                        "buffering_mb": .int(0),
                        "clear_on_media_end": .bool(false),
                        "close_when_inactive": .bool(false),
                        "ffmpeg_options": .string("rtsp_transport=tcp"),
                        "hw_decode": .bool(false),
                        "input": .string("rtsp://localhost:8554/example"),
                        "is_local_file": .bool(false),
                        "reconnect_delay_sec": .int(1),
                        "restart_on_activate": .bool(false)
                    ]
                )
            ]
        )
        let provisioner = OBSRTSPSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [source])

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(report.createdInputs, [source.managedOBSInputName])
        XCTAssertEqual(client.createdInputs.first?.inputKind, "ffmpeg_source")
        XCTAssertEqual(client.createdInputs.first?.inputSettings["input"], .string("rtsp://127.0.0.1:8554/camera_kitchen"))
        XCTAssertEqual(client.createdInputs.first?.inputSettings["is_local_file"], .bool(false))
        XCTAssertEqual(client.createdInputs.first?.inputSettings["ffmpeg_options"], .string("rtsp_transport=tcp"))
    }

    func testIncorrectExistingRTSPInputIsUpdated() async {
        let source = makeRTSPCamera(name: "Kitchen", streamURL: "rtsp://127.0.0.1:8554/camera_kitchen")
        let inputName = source.managedOBSInputName
        let sceneName = source.managedOBSSceneName
        let client = MockOBSProvisioningClient(
            scenes: [sceneName],
            inputKinds: ["ffmpeg_source"],
            defaultSettingsByKind: ["ffmpeg_source": [:]],
            inputs: [
                "Example RTSP": MockOBSProvisioningClient.InputState(
                    kind: "ffmpeg_source",
                    settings: [
                        "buffering_mb": .int(0),
                        "clear_on_media_end": .bool(false),
                        "close_when_inactive": .bool(false),
                        "ffmpeg_options": .string("rtsp_transport=tcp"),
                        "hw_decode": .bool(false),
                        "input": .string("rtsp://localhost:8554/example"),
                        "is_local_file": .bool(false),
                        "reconnect_delay_sec": .int(1),
                        "restart_on_activate": .bool(false)
                    ]
                ),
                inputName: MockOBSProvisioningClient.InputState(
                    kind: "ffmpeg_source",
                    settings: [
                        "buffering_mb": .int(0),
                        "clear_on_media_end": .bool(false),
                        "close_when_inactive": .bool(false),
                        "ffmpeg_options": .string("rtsp_transport=tcp"),
                        "hw_decode": .bool(false),
                        "input": .string("rtsp://127.0.0.1:8554/wrong"),
                        "is_local_file": .bool(false),
                        "reconnect_delay_sec": .int(1),
                        "restart_on_activate": .bool(false)
                    ]
                )
            ],
            sceneItems: [sceneName: [inputName: 45]]
        )
        let provisioner = OBSRTSPSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [source])

        XCTAssertEqual(report.updatedInputs, [inputName])
        XCTAssertEqual(client.inputs[inputName]?.settings["input"], .string("rtsp://127.0.0.1:8554/camera_kitchen"))
    }

    func testInvalidRTSPSourceIsIgnoredByRTSPProvisioner() async {
        let invalid = CameraDefinition(name: "Bad RTSP", providerType: .ffmpeg, streamURL: "http://127.0.0.1/not-rtsp", isEnabled: true)
        let client = MockOBSProvisioningClient(
            inputKinds: ["ffmpeg_source"],
            defaultSettingsByKind: ["ffmpeg_source": [:]]
        )
        let provisioner = OBSRTSPSceneProvisioner(client: client)

        let report = await provisioner.synchronize(sources: [invalid])

        XCTAssertEqual(report, .empty)
        XCTAssertTrue(client.createdSceneNames.isEmpty)
        XCTAssertTrue(client.createdInputs.isEmpty)
    }

    private func makeLocalCamera(name: String, deviceID: String) -> CameraDefinition {
        CameraDefinition(
            id: UUID(),
            name: name,
            sceneName: "",
            providerType: .localCamera,
            streamURL: "",
            localDeviceUniqueID: deviceID,
            isEnabled: true
        )
    }

    private func makeRTSPCamera(name: String, streamURL: String) -> CameraDefinition {
        CameraDefinition(
            id: UUID(),
            name: name,
            sceneName: "",
            providerType: .ffmpeg,
            streamURL: streamURL,
            isEnabled: true
        )
    }
}

@MainActor
private final class MockOBSProvisioningClient: OBSProvisioningClient {
    struct InputState {
        var kind: String
        var settings: [String: JSONValue]
    }

    struct CreatedInputCall: Equatable {
        let sceneName: String
        let inputName: String
        let inputKind: String
        let inputSettings: [String: JSONValue]
    }

    struct CreatedSceneItemCall: Equatable {
        let sceneName: String
        let sourceName: String
    }

    var connectionState: OBSConnectionState = .connected
    var currentProgramSceneName: String?
    private(set) var availableScenes: [OBSSceneSummary] = []

    private(set) var scenes: Set<String>
    private(set) var inputKinds: [String]
    private(set) var defaultSettingsByKind: [String: [String: JSONValue]]
    fileprivate var inputs: [String: InputState]
    private(set) var sceneItems: [String: [String: Int]]
    private(set) var videoSettings: OBSVideoSettings
    private(set) var propertyItemsByInputAndProperty: [String: [String: [OBSPropertyListItem]]]
    private(set) var createdSceneNames: [String] = []
    private(set) var createdInputs: [CreatedInputCall] = []
    private(set) var updatedInputNames: [String] = []
    private(set) var createdSceneItems: [CreatedSceneItemCall] = []
    private(set) var lastTransformBySceneItemID: [Int: OBSSceneItemTransformSettings] = [:]
    private(set) var lockedSceneItemIDs: [Int: Bool] = [:]
    private let failingCreateInputNames: Set<String>
    private var nextSceneItemID = 100

    init(
        scenes: [String] = [],
        inputKinds: [String],
        defaultSettingsByKind: [String: [String: JSONValue]],
        inputs: [String: InputState] = [:],
        sceneItems: [String: [String: Int]] = [:],
        propertyItemsByInputAndProperty: [String: [String: [OBSPropertyListItem]]] = [:],
        videoSettings: OBSVideoSettings = OBSVideoSettings(baseWidth: 1920, baseHeight: 1080),
        failingCreateInputNames: Set<String> = []
    ) {
        self.scenes = Set(scenes)
        self.inputKinds = inputKinds
        self.defaultSettingsByKind = defaultSettingsByKind
        self.inputs = inputs
        self.sceneItems = sceneItems
        self.propertyItemsByInputAndProperty = propertyItemsByInputAndProperty
        self.videoSettings = videoSettings
        self.failingCreateInputNames = failingCreateInputNames
    }

    func refreshSceneList() async {
        availableScenes = scenes.sorted().map(OBSSceneSummary.init(name:))
    }

    func setCurrentProgramScene(sceneName: String) async {
        currentProgramSceneName = sceneName
    }

    func getSceneList() async throws -> [OBSSceneSummary] {
        scenes.sorted().map(OBSSceneSummary.init(name:))
    }

    func createScene(named sceneName: String) async throws {
        createdSceneNames.append(sceneName)
        scenes.insert(sceneName)
    }

    func getInputList(inputKind: String?) async throws -> [OBSInputSummary] {
        inputs.compactMap { name, input in
            guard inputKind == nil || input.kind == inputKind else { return nil }
            return OBSInputSummary(id: name, inputName: name, inputKind: input.kind, unversionedInputKind: nil)
        }
    }

    func getInputKindList(unversioned: Bool) async throws -> [String] {
        inputKinds
    }

    func getInputDefaultSettings(inputKind: String) async throws -> [String: JSONValue] {
        defaultSettingsByKind[inputKind] ?? [:]
    }

    func getInputSettings(inputName: String) async throws -> (inputKind: String, inputSettings: [String: JSONValue]) {
        guard let input = inputs[inputName] else {
            throw MockError.missingInput(inputName)
        }

        return (input.kind, input.settings)
    }

    func getInputPropertiesListPropertyItems(
        inputName: String,
        propertyName: String
    ) async throws -> [OBSPropertyListItem] {
        if let items = propertyItemsByInputAndProperty[inputName]?[propertyName] {
            return items
        }
        throw MockError.missingPropertyItems(inputName, propertyName)
    }

    func createInput(
        sceneName: String,
        inputName: String,
        inputKind: String,
        inputSettings: [String: JSONValue],
        sceneItemEnabled: Bool
    ) async throws {
        if failingCreateInputNames.contains(inputName) {
            throw MockError.failedCreateInput(inputName)
        }

        createdInputs.append(
            CreatedInputCall(
                sceneName: sceneName,
                inputName: inputName,
                inputKind: inputKind,
                inputSettings: inputSettings
            )
        )
        inputs[inputName] = InputState(kind: inputKind, settings: inputSettings)
        sceneItems[sceneName, default: [:]][inputName] = nextSceneItemID
        nextSceneItemID += 1
    }

    func setInputSettings(inputName: String, inputSettings: [String: JSONValue], overlay: Bool) async throws {
        guard var input = inputs[inputName] else {
            throw MockError.missingInput(inputName)
        }

        updatedInputNames.append(inputName)
        input.settings = inputSettings
        inputs[inputName] = input
    }

    func createSceneItem(
        sceneName: String,
        sourceName: String,
        sceneItemEnabled: Bool
    ) async throws -> Int {
        guard inputs[sourceName] != nil else {
            throw MockError.missingInput(sourceName)
        }

        let sceneItemId = nextSceneItemID
        nextSceneItemID += 1
        createdSceneItems.append(CreatedSceneItemCall(sceneName: sceneName, sourceName: sourceName))
        sceneItems[sceneName, default: [:]][sourceName] = sceneItemId
        return sceneItemId
    }

    func getSceneItemId(sceneName: String, sourceName: String) async throws -> Int {
        guard let id = sceneItems[sceneName]?[sourceName] else {
            throw MockError.missingSceneItem(sceneName, sourceName)
        }

        return id
    }

    func getSceneItemTransform(sceneName: String, sceneItemId: Int) async throws -> OBSSceneItemTransformSettings {
        lastTransformBySceneItemID[sceneItemId] ?? OBSSceneItemTransformSettings(
            positionX: 10,
            positionY: 10,
            alignment: 5,
            boundsType: "OBS_BOUNDS_NONE",
            boundsAlignment: 5,
            boundsWidth: 640,
            boundsHeight: 360
        )
    }

    func setSceneItemTransform(sceneName: String, sceneItemId: Int, transform: OBSSceneItemTransformSettings) async throws {
        lastTransformBySceneItemID[sceneItemId] = transform
    }

    func setSceneItemLocked(sceneName: String, sceneItemId: Int, locked: Bool) async throws {
        lockedSceneItemIDs[sceneItemId] = locked
    }

    func getVideoSettings() async throws -> OBSVideoSettings {
        videoSettings
    }
}

private extension MockOBSProvisioningClient {
    enum MockError: LocalizedError {
        case missingInput(String)
        case missingSceneItem(String, String)
        case missingPropertyItems(String, String)
        case failedCreateInput(String)

        var errorDescription: String? {
            switch self {
            case .missingInput(let inputName):
                return "Missing input \(inputName)"
            case .missingSceneItem(let sceneName, let sourceName):
                return "Missing scene item \(sourceName) in scene \(sceneName)"
            case .missingPropertyItems(let inputName, let propertyName):
                return "Missing property items \(propertyName) for \(inputName)"
            case .failedCreateInput(let inputName):
                return "Failed to create input \(inputName)"
            }
        }
    }
}

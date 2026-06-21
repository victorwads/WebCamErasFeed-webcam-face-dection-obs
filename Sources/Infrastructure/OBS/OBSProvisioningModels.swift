import Foundation

struct OBSResolvedCameraInput: Sendable, Equatable {
    let inputKind: String
    let defaultSettings: [String: JSONValue]
}

struct OBSInputSummary: Identifiable, Sendable, Equatable {
    let id: String
    let inputName: String
    let inputKind: String
    let unversionedInputKind: String?
}

struct OBSPropertyListItem: Sendable, Equatable {
    let itemName: String
    let itemValue: String
    let itemEnabled: Bool
}

struct OBSVideoSettings: Sendable, Equatable {
    let baseWidth: Int
    let baseHeight: Int
}

struct OBSSceneItemTransformSettings: Sendable, Equatable {
    let positionX: Double
    let positionY: Double
    let alignment: Int
    let boundsType: String
    let boundsAlignment: Int
    let boundsWidth: Double
    let boundsHeight: Double

    // OBS uses a bitmask alignment model where 0 means centered.
    private static let centeredAlignment = 0

    static func fillCanvas(width: Int, height: Int) -> OBSSceneItemTransformSettings {
        OBSSceneItemTransformSettings(
            positionX: Double(width) / 2,
            positionY: Double(height) / 2,
            alignment: centeredAlignment,
            boundsType: "OBS_BOUNDS_SCALE_INNER",
            boundsAlignment: centeredAlignment,
            boundsWidth: Double(width),
            boundsHeight: Double(height)
        )
    }

    var requestData: [String: JSONValue] {
        [
            "positionX": .double(positionX),
            "positionY": .double(positionY),
            "alignment": .int(alignment),
            "boundsType": .string(boundsType),
            "boundsAlignment": .int(boundsAlignment),
            "boundsWidth": .double(boundsWidth),
            "boundsHeight": .double(boundsHeight)
        ]
    }

    static func from(responseObject: [String: JSONValue]) -> OBSSceneItemTransformSettings? {
        guard
            let positionX = responseObject["positionX"]?.doubleValue,
            let positionY = responseObject["positionY"]?.doubleValue,
            let alignment = responseObject["alignment"]?.intValue,
            let boundsType = responseObject["boundsType"]?.stringValue,
            let boundsAlignment = responseObject["boundsAlignment"]?.intValue,
            let boundsWidth = responseObject["boundsWidth"]?.doubleValue,
            let boundsHeight = responseObject["boundsHeight"]?.doubleValue
        else {
            return nil
        }

        return OBSSceneItemTransformSettings(
            positionX: positionX,
            positionY: positionY,
            alignment: alignment,
            boundsType: boundsType,
            boundsAlignment: boundsAlignment,
            boundsWidth: boundsWidth,
            boundsHeight: boundsHeight
        )
    }
}

struct OBSLocalCameraProvisioningError: Identifiable, Error, Sendable, Equatable {
    let id = UUID()
    let sourceID: UUID
    let sourceName: String
    let message: String
}

struct OBSLocalCameraProvisioningReport: Sendable, Equatable {
    let createdScenes: [String]
    let createdInputs: [String]
    let updatedInputs: [String]
    let unchangedInputs: [String]
    let errors: [OBSLocalCameraProvisioningError]

    static let empty = OBSLocalCameraProvisioningReport(
        createdScenes: [],
        createdInputs: [],
        updatedInputs: [],
        unchangedInputs: [],
        errors: []
    )

    var summaryText: String {
        var parts: [String] = []
        if !createdScenes.isEmpty {
            parts.append("Scenes created: \(createdScenes.count)")
        }
        if !createdInputs.isEmpty {
            parts.append("Inputs created: \(createdInputs.count)")
        }
        if !updatedInputs.isEmpty {
            parts.append("Inputs updated: \(updatedInputs.count)")
        }
        if !unchangedInputs.isEmpty {
            parts.append("Inputs unchanged: \(unchangedInputs.count)")
        }
        if !errors.isEmpty {
            parts.append("Errors: \(errors.count)")
        }
        return parts.isEmpty ? "No OBS local camera changes were required." : parts.joined(separator: " | ")
    }
}

@MainActor
protocol OBSProvisioningClient: AnyObject {
    var connectionState: OBSConnectionState { get }
    var currentProgramSceneName: String? { get }

    func refreshSceneList() async
    func setCurrentProgramScene(sceneName: String) async
    func getSceneList() async throws -> [OBSSceneSummary]
    func createScene(named sceneName: String) async throws
    func getInputList(inputKind: String?) async throws -> [OBSInputSummary]
    func getInputKindList(unversioned: Bool) async throws -> [String]
    func getInputDefaultSettings(inputKind: String) async throws -> [String: JSONValue]
    func getInputSettings(inputName: String) async throws -> (inputKind: String, inputSettings: [String: JSONValue])
    func getInputPropertiesListPropertyItems(
        inputName: String,
        propertyName: String
    ) async throws -> [OBSPropertyListItem]
    func createInput(
        sceneName: String,
        inputName: String,
        inputKind: String,
        inputSettings: [String: JSONValue],
        sceneItemEnabled: Bool
    ) async throws
    func createSceneItem(
        sceneName: String,
        sourceName: String,
        sceneItemEnabled: Bool
    ) async throws -> Int
    func setInputSettings(
        inputName: String,
        inputSettings: [String: JSONValue],
        overlay: Bool
    ) async throws
    func getSceneItemId(sceneName: String, sourceName: String) async throws -> Int
    func getSceneItemTransform(sceneName: String, sceneItemId: Int) async throws -> OBSSceneItemTransformSettings
    func setSceneItemTransform(
        sceneName: String,
        sceneItemId: Int,
        transform: OBSSceneItemTransformSettings
    ) async throws
    func setSceneItemLocked(
        sceneName: String,
        sceneItemId: Int,
        locked: Bool
    ) async throws
    func getVideoSettings() async throws -> OBSVideoSettings
}

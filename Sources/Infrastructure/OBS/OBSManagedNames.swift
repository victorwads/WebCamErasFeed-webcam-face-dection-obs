import Foundation

struct OBSManagedNames {
    static func sceneName(for source: CameraDefinition) -> String {
        "[CameraDirector] \(source.displayName)"
    }

    static func inputName(for source: CameraDefinition) -> String {
        "[CameraDirector] Camera - \(source.id.uuidString)"
    }
}

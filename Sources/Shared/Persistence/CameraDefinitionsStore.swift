import Foundation

struct CameraDefinitionsStore {
    private let defaults: UserDefaults
    private let key = "cameraDirector.cameraDefinitions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [CameraDefinition] {
        guard
            let data = defaults.data(forKey: key),
            let cameras = try? JSONDecoder().decode([CameraDefinition].self, from: data)
        else {
            return []
        }

        return cameras
    }

    func save(_ cameras: [CameraDefinition]) {
        let filtered = cameras.filter { !$0.isEmpty }
        guard let data = try? JSONEncoder().encode(filtered) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

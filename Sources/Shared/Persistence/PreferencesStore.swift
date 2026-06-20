import Foundation

struct PreferencesStore {
    private let defaults: UserDefaults
    private let key = "cameraDirector.preferences"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppPreferences {
        guard
            let data = defaults.data(forKey: key),
            let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else {
            return .default
        }

        var normalized = preferences
        normalized.captureInterval = normalized.clampedCaptureInterval
        return normalized
    }

    func save(_ preferences: AppPreferences) {
        var normalized = preferences
        normalized.captureInterval = normalized.clampedCaptureInterval

        guard let data = try? JSONEncoder().encode(normalized) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

import Foundation

@MainActor
final class WebViewWindowManager {
    private var controllers: [UUID: WebViewWindowController] = [:]

    func syncWindows(with configurations: [CameraDefinition]) {
        let activeWebViewConfigurations = Dictionary(
            uniqueKeysWithValues: configurations
                .filter { $0.isEnabled && $0.providerType == .webView }
                .map { ($0.id, $0) }
        )

        for (sourceID, controller) in controllers {
            guard let configuration = activeWebViewConfigurations[sourceID] else {
                controller.closeWindow()
                controllers.removeValue(forKey: sourceID)
                AppLog.webView.info("Closed WebView window for inactive source \(sourceID.uuidString, privacy: .public)")
                continue
            }

            controller.sync(with: configuration)
        }
    }

    func ensureWindow(for configuration: CameraDefinition) throws -> WebViewWindowController {
        guard configuration.providerType == .webView else {
            throw FrameProviderError.invalidConfiguration("The selected source is not a WebView provider.")
        }

        guard configuration.hasValidWebViewURL else {
            throw FrameProviderError.invalidConfiguration("A valid HTTP or HTTPS WebView URL is required.")
        }

        if let existing = controllers[configuration.id] {
            existing.sync(with: configuration)
            return existing
        }

        let controller = WebViewWindowController(configuration: configuration)
        controllers[configuration.id] = controller
        AppLog.webView.info("Created WebView window for source \(configuration.id.uuidString, privacy: .public)")
        return controller
    }

    func openWindow(for configuration: CameraDefinition) throws {
        let controller = try ensureWindow(for: configuration)
        controller.openWindow()
    }

    func reloadWindow(for configuration: CameraDefinition) throws {
        let controller = try ensureWindow(for: configuration)
        controller.reload()
    }

    func showWindow(for sourceID: UUID) {
        controllers[sourceID]?.showWindow()
    }

    func hideWindow(for sourceID: UUID) {
        controllers[sourceID]?.hideWindow()
    }

    func bringWindowToFront(for sourceID: UUID) {
        controllers[sourceID]?.bringToFront()
    }

    func controller(for sourceID: UUID) -> WebViewWindowController? {
        controllers[sourceID]
    }

    func status(for sourceID: UUID) -> WebViewWindowRuntimeStatus? {
        controllers[sourceID]?.statusSnapshot()
    }

    func removeWindow(for sourceID: UUID) {
        controllers[sourceID]?.closeWindow()
        controllers.removeValue(forKey: sourceID)
    }
}

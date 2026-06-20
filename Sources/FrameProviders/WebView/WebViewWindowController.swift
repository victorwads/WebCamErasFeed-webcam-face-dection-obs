import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewWindowController: NSObject, NSWindowDelegate {
    let sourceID: UUID

    private(set) var configuration: CameraDefinition
    private let webView: WKWebView
    private let navigationDelegate = WebViewNavigationDelegate()
    private let window: NSWindow

    private var navigationStatus = "Idle"
    private var lastError: String?

    init(configuration: CameraDefinition) {
        self.sourceID = configuration.id
        self.configuration = configuration

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.enclosingScrollView?.drawsBackground = false
        self.webView = webView

        let origin = CGPoint(
            x: configuration.webViewWindowOriginX ?? 120,
            y: configuration.webViewWindowOriginY ?? 120
        )
        let frame = CGRect(
            origin: origin,
            size: CGSize(width: configuration.webViewWidth, height: configuration.webViewHeight)
        )

        self.window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary, .managed]
        window.title = configuration.webViewWindowTitle
        window.contentView = webView

        navigationDelegate.onStatusChange = { [weak self] status, error in
            guard let self else { return }
            self.navigationStatus = status
            self.lastError = error
        }
        webView.navigationDelegate = navigationDelegate
    }

    func sync(with configuration: CameraDefinition) {
        self.configuration = configuration
        window.title = configuration.webViewWindowTitle
        window.setFrame(
            CGRect(
                origin: CGPoint(
                    x: configuration.webViewWindowOriginX ?? window.frame.origin.x,
                    y: configuration.webViewWindowOriginY ?? window.frame.origin.y
                ),
                size: CGSize(width: configuration.webViewWidth, height: configuration.webViewHeight)
            ),
            display: true,
            animate: false
        )

        if webView.url?.absoluteString != configuration.trimmedStreamURL {
            loadCurrentURL()
        }
    }

    func openWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webView.url == nil {
            loadCurrentURL()
        }
    }

    func reload() {
        if webView.url == nil {
            loadCurrentURL()
        } else {
            webView.reload()
        }
    }

    func showWindow() {
        window.orderFrontRegardless()
    }

    func hideWindow() {
        window.orderOut(nil)
    }

    func bringToFront() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func loadCurrentURL() {
        guard let url = URL(string: configuration.trimmedStreamURL) else {
            navigationStatus = "Invalid URL"
            lastError = "The configured WebView URL is invalid."
            return
        }

        navigationStatus = "Loading"
        lastError = nil
        webView.load(URLRequest(url: url))
    }

    func statusSnapshot() -> WebViewWindowRuntimeStatus {
        WebViewWindowRuntimeStatus(
            sourceID: sourceID,
            windowTitle: window.title,
            loadedURL: webView.url?.absoluteString ?? configuration.trimmedStreamURL.nilIfEmpty,
            isWindowOpen: true,
            isVisible: window.isVisible,
            isLoading: webView.isLoading,
            navigationStatus: navigationStatus,
            windowStatus: window.isVisible ? "Visible" : "Hidden",
            lastError: lastError,
            windowID: window.windowNumber > 0 ? CGWindowID(window.windowNumber) : nil
        )
    }

    func windowDidMove(_ notification: Notification) {
        configuration.webViewWindowOriginX = window.frame.origin.x
        configuration.webViewWindowOriginY = window.frame.origin.y
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

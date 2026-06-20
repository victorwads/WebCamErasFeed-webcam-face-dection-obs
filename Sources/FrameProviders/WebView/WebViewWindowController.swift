import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewWindowController: NSObject, NSWindowDelegate {
    let sourceID: UUID

    private(set) var configuration: CameraDefinition
    private let webView: WKWebView
    private let navigationDelegate = WebViewNavigationDelegate()
    private let window: FocusFriendlyWindow
    private let statusLabel = NSTextField(labelWithString: "Idle")
    private let titleLabel = NSTextField(labelWithString: "")

    private var navigationStatus = "Idle" {
        didSet {
            updateStatusLabel()
        }
    }
    private var lastError: String? {
        didSet {
            updateStatusLabel()
        }
    }
    private var keepAliveTimer: Timer?

    init(configuration: CameraDefinition) {
        self.sourceID = configuration.id
        self.configuration = configuration

        let userContentController = WKUserContentController()
        let focusScript = WKUserScript(
            source: """
            document.hasFocus = () => true;
            Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
            Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
            Object.defineProperty(document, 'webkitHidden', { configurable: true, get: () => false });
            Object.defineProperty(document, 'webkitVisibilityState', { configurable: true, get: () => 'visible' });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(focusScript)

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController = userContentController
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
        webConfiguration.preferences.setValue(true, forKey: "developerExtrasEnabled")

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

        self.window = FocusFriendlyWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configureWindow()
        configureContent()
        configureDelegates()
    }

    deinit {
        keepAliveTimer?.invalidate()
    }

    func sync(with configuration: CameraDefinition) {
        self.configuration = configuration
        window.title = configuration.webViewWindowTitle
        titleLabel.stringValue = configuration.webViewWindowTitle
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
        window.makeFirstResponder(webView)
        startKeepAliveTimerIfNeeded()
        maintainPlaybackAndFocus()
        if webView.url == nil {
            loadCurrentURL()
        }
    }

    func reload() {
        maintainPlaybackAndFocus()
        if webView.url == nil {
            loadCurrentURL()
        } else {
            webView.reloadFromOrigin()
        }
    }

    func showWindow() {
        window.orderFrontRegardless()
        startKeepAliveTimerIfNeeded()
        maintainPlaybackAndFocus()
    }

    func hideWindow() {
        window.orderOut(nil)
    }

    func closeWindow() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        webView.stopLoading()
        window.orderOut(nil)
        window.close()
    }

    func bringToFront() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(webView)
        maintainPlaybackAndFocus()
    }

    func loadCurrentURL() {
        guard let url = URL(string: configuration.trimmedStreamURL) else {
            navigationStatus = "Invalid URL"
            lastError = "The configured WebView URL is invalid."
            return
        }

        navigationStatus = "Loading"
        lastError = nil
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        webView.load(request)
        startKeepAliveTimerIfNeeded()
    }

    func statusSnapshot() -> WebViewWindowRuntimeStatus {
        let visibilityDescription: String
        if window.isVisible {
            visibilityDescription = window.isKeyWindow ? "Visible, focused and draggable" : "Visible, focus spoof active and draggable"
        } else {
            visibilityDescription = "Hidden"
        }

        return WebViewWindowRuntimeStatus(
            sourceID: sourceID,
            windowTitle: window.title,
            loadedURL: webView.url?.absoluteString ?? configuration.trimmedStreamURL.nilIfEmpty,
            isWindowOpen: true,
            isVisible: window.isVisible,
            isKeyWindow: window.isKeyWindow,
            isLoading: webView.isLoading,
            navigationStatus: navigationStatus,
            windowStatus: visibilityDescription,
            lastError: lastError,
            windowID: window.windowNumber > 0 ? CGWindowID(window.windowNumber) : nil
        )
    }

    func windowDidMove(_ notification: Notification) {
        configuration.webViewWindowOriginX = window.frame.origin.x
        configuration.webViewWindowOriginY = window.frame.origin.y
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window.makeFirstResponder(webView)
        maintainPlaybackAndFocus()
    }

    func windowDidResignKey(_ notification: Notification) {
        maintainPlaybackAndFocus()
    }

    private func configureWindow() {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary, .managed]
        window.title = configuration.webViewWindowTitle
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.hidesOnDeactivate = false
        titleLabel.stringValue = configuration.webViewWindowTitle
    }

    private func configureContent() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor

        let titleBar = DraggableTitleBarView()
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        let reloadButton = NSButton(title: "Reload", target: self, action: #selector(reloadFromWindowChrome))
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.bezelStyle = .rounded
        reloadButton.controlSize = .small

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = navigationDelegate

        titleBar.addSubview(titleLabel)
        titleBar.addSubview(statusLabel)
        titleBar.addSubview(reloadButton)

        rootView.addSubview(titleBar)
        rootView.addSubview(webView)
        window.contentView = rootView

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: rootView.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 34),

            titleLabel.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 12),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: reloadButton.leadingAnchor, constant: -8),

            reloadButton.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -10),
            reloadButton.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),

            webView.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        updateStatusLabel()
    }

    private func configureDelegates() {
        navigationDelegate.onStatusChange = { [weak self] status, error in
            guard let self else { return }
            self.navigationStatus = status
            self.lastError = error
        }
        navigationDelegate.onKeepAliveRequested = { [weak self] in
            self?.maintainPlaybackAndFocus()
        }
    }

    @objc
    private func reloadFromWindowChrome() {
        reload()
    }

    private func updateStatusLabel() {
        let base = navigationStatus
        if let lastError, !lastError.isEmpty {
            statusLabel.stringValue = "\(base) • \(lastError)"
            statusLabel.textColor = .systemRed
        } else {
            let focusStatus = window.isKeyWindow ? "native focus active" : "focus spoof active"
            statusLabel.stringValue = "\(base) • localhost WebRTC allowed • \(focusStatus)"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    private func startKeepAliveTimerIfNeeded() {
        guard keepAliveTimer == nil else { return }

        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.maintainPlaybackAndFocus()
            }
        }
        RunLoop.main.add(keepAliveTimer!, forMode: .common)
    }

    private func maintainPlaybackAndFocus() {
        guard window.isVisible else { return }
        window.makeFirstResponder(webView)
        navigationDelegate.maintainPlaybackAndFocus(in: webView)
    }
}

@MainActor
private final class FocusFriendlyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class DraggableTitleBarView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

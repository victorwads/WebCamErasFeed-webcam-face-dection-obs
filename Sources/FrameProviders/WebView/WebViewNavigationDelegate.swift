import Foundation
import WebKit

@MainActor
final class WebViewNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    var onStatusChange: ((String, String?) -> Void)?
    var onKeepAliveRequested: (() -> Void)?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onStatusChange?("Loading", nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onStatusChange?("Loaded", nil)
        maintainPlaybackAndFocus(in: webView)
        onKeepAliveRequested?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onStatusChange?("Navigation Failed", error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        onStatusChange?("Provisional Load Failed", error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onStatusChange?("Web Content Restarted", "The embedded browser process terminated and will reload.")
        webView.reload()
    }

    func webViewDidClose(_ webView: WKWebView) {
        onStatusChange?("Closed", nil)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        let isAllowedLocalhost = host == "localhost" || host == "127.0.0.1" || host == "::1"

        guard isAllowedLocalhost else {
            onStatusChange?("Media Permission Denied", "WebRTC media capture is only allowed for localhost sources.")
            decisionHandler(.deny)
            return
        }

        switch type {
        case .camera:
            decisionHandler(.grant)
        case .microphone, .cameraAndMicrophone:
            onStatusChange?("Microphone Blocked", "CameraDirector blocks microphone access for WebView sources.")
            decisionHandler(.deny)
        @unknown default:
            decisionHandler(.deny)
        }
    }

    func maintainPlaybackAndFocus(in webView: WKWebView) {
        let script = """
        (() => {
            try {
                document.hasFocus = () => true;
                Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
                Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
                Object.defineProperty(document, 'webkitHidden', { configurable: true, get: () => false });
                Object.defineProperty(document, 'webkitVisibilityState', { configurable: true, get: () => 'visible' });
                window.onblur = null;
                window.onfocus = null;
                window.focus();
                document.dispatchEvent(new Event('visibilitychange'));
                window.dispatchEvent(new Event('focus'));
                const media = document.querySelectorAll('video, audio');
                media.forEach((element) => {
                    element.muted = true;
                    element.volume = 0;
                    element.autoplay = true;
                    element.playsInline = true;
                    const promise = element.play?.();
                    if (promise && promise.catch) {
                        promise.catch(() => {});
                    }
                });
            } catch (_) {}
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

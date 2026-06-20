import Foundation
import WebKit

@MainActor
final class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {
    var onStatusChange: ((String, String?) -> Void)?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onStatusChange?("Loading", nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onStatusChange?("Loaded", nil)
        muteAndAutoplayMedia(in: webView)
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

    private func muteAndAutoplayMedia(in webView: WKWebView) {
        let script = """
        (() => {
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
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

import CoreGraphics
import Foundation

struct WebViewWindowRuntimeStatus: Sendable {
    let sourceID: UUID
    let windowTitle: String
    let loadedURL: String?
    let isWindowOpen: Bool
    let isVisible: Bool
    let isLoading: Bool
    let navigationStatus: String
    let windowStatus: String
    let lastError: String?
    let windowID: CGWindowID?
}

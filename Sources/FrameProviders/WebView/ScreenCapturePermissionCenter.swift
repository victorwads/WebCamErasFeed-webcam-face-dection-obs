import CoreGraphics
import Foundation

enum ScreenCapturePermissionCenter {
    static func hasAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccessIfNeeded() -> Bool {
        hasAccess() || CGRequestScreenCaptureAccess()
    }
}

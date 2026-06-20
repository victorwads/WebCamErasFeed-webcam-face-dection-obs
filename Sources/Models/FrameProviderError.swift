import Foundation

enum FrameProviderError: LocalizedError, Sendable {
    case frameUnavailable
    case invalidConfiguration(String)
    case ffmpegNotFound
    case screenCapturePermissionDenied
    case screenCaptureWindowUnavailable
    case webViewLoadFailed(String)
    case localCameraPermissionDenied
    case localCameraUnavailable

    var errorDescription: String? {
        switch self {
        case .frameUnavailable:
            return "No frame is available yet for this source."
        case .invalidConfiguration(let message):
            return message
        case .ffmpegNotFound:
            return "FFmpeg was not found. Install it with Homebrew or place it in a supported path."
        case .screenCapturePermissionDenied:
            return "Screen recording permission is required. Open System Settings > Privacy & Security > Screen Recording and allow CameraDirector."
        case .screenCaptureWindowUnavailable:
            return "The WebView window could not be located for ScreenCaptureKit."
        case .webViewLoadFailed(let message):
            return "The WebView source failed to load: \(message)"
        case .localCameraPermissionDenied:
            return "Camera permission is required to capture frames from the local webcam."
        case .localCameraUnavailable:
            return "The selected local camera is unavailable."
        }
    }
}

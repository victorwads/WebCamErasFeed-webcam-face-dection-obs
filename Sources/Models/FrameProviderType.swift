import Foundation

enum FrameProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    case ffmpeg
    case webView
    case localCamera

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ffmpeg:
            return "FFmpeg RTSP"
        case .webView:
            return "WebView WebRTC"
        case .localCamera:
            return "Local Camera"
        }
    }

    init(legacyValue: String?) {
        switch legacyValue {
        case FrameProviderType.localCamera.rawValue:
            self = .localCamera
        case FrameProviderType.webView.rawValue:
            self = .webView
        case "networkStream":
            self = .ffmpeg
        default:
            self = .ffmpeg
        }
    }
}

typealias CameraSourceType = FrameProviderType

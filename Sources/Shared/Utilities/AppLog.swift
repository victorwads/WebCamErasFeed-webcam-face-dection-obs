import OSLog

enum AppLog {
    static let frameProvider = Logger(subsystem: "com.victorwads.CameraDirector", category: "FrameProvider")
    static let frameCapture = Logger(subsystem: "com.victorwads.CameraDirector", category: "FrameCapture")
    static let ffmpeg = Logger(subsystem: "com.victorwads.CameraDirector", category: "FFmpeg")
    static let webView = Logger(subsystem: "com.victorwads.CameraDirector", category: "WebView")
    static let screenCapture = Logger(subsystem: "com.victorwads.CameraDirector", category: "ScreenCapture")
    static let localCamera = Logger(subsystem: "com.victorwads.CameraDirector", category: "LocalCamera")
    static let vision = Logger(subsystem: "com.victorwads.CameraDirector", category: "Vision")
    static let obs = Logger(subsystem: "com.victorwads.CameraDirector", category: "OBS")
    static let cameraSelection = Logger(subsystem: "com.victorwads.CameraDirector", category: "CameraSelection")
}

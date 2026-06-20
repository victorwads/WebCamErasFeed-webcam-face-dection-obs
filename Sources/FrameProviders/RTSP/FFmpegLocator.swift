import Foundation

struct FFmpegLocator {
    static let commonPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]

    func locate() -> String? {
        let fileManager = FileManager.default
        return Self.commonPaths.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }
}

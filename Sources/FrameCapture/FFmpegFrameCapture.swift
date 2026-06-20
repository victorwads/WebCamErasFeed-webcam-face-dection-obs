import Foundation

enum FFmpegFrameCaptureError: LocalizedError {
    case ffmpegNotFound
    case invalidImageData
    case emptyOutput
    case commandFailed(message: String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg was not found. Install it with Homebrew or place it in a supported path."
        case .invalidImageData:
            return "FFmpeg returned data, but it was not a valid image."
        case .emptyOutput:
            return "FFmpeg did not return any frame data."
        case .commandFailed(let message):
            return message.isEmpty ? "FFmpeg failed to capture a frame." : message
        case .timedOut:
            return "Frame capture timed out."
        }
    }
}

struct FFmpegFrameCapture {
    let ffmpegPath: String
    var timeoutSeconds: Double = 8

    func captureFrame(for camera: CameraDefinition) async throws -> DecodedFrame {
        try await withTimeout(seconds: timeoutSeconds) {
            try await runCapture(for: camera)
        }
    }

    private func runCapture(for camera: CameraDefinition) async throws -> DecodedFrame {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-rtsp_transport", "tcp",
            "-i", camera.trimmedStreamURL,
            "-frames:v", "1",
            "-vf", "scale=960:-1",
            "-f", "image2pipe",
            "-vcodec", "mjpeg",
            "pipe:1"
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withTaskCancellationHandler {
            try process.run()

            async let outputData = stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
            async let errorData = stderrPipe.fileHandleForReading.readToEnd() ?? Data()
            async let exitCode = waitForExit(of: process)

            let output = try await outputData
            let stderr = try await errorData
            let status = await exitCode

            if status != 0 {
                let message = String(data: stderr, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw FFmpegFrameCaptureError.commandFailed(
                    message: message.isEmpty ? "FFmpeg exited with status \(status)." : message
                )
            }

            guard !output.isEmpty else {
                throw FFmpegFrameCaptureError.emptyOutput
            }

            return try RawFrameDecoder.decodeImageData(output)
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func waitForExit(of process: Process) async -> Int32 {
        await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                let duration = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: duration)
                throw FFmpegFrameCaptureError.timedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

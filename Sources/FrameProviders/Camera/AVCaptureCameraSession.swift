import AVFoundation
import CoreImage
import Foundation

final class AVCaptureCameraSession: NSObject, @unchecked Sendable {
    private let sourceID: UUID
    private let deviceUniqueID: String
    private let providerType: FrameProviderType
    private let targetSize: CGSize
    private let sessionQueue = DispatchQueue(label: "CameraDirector.LocalCamera.Session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "CameraDirector.LocalCamera.Output", qos: .userInitiated)
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: nil)
    private var sequence: UInt64 = 0

    var onFrame: (@Sendable (CapturedFrame) -> Void)?

    init(sourceID: UUID, deviceUniqueID: String, providerType: FrameProviderType, targetSize: CGSize) {
        self.sourceID = sourceID
        self.deviceUniqueID = deviceUniqueID
        self.providerType = providerType
        self.targetSize = targetSize
        super.init()
    }

    func start() throws {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = LocalCameraErrorBox()

        sessionQueue.async {
            defer { semaphore.signal() }

            do {
                try self.configureIfNeeded()
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
            } catch {
                errorBox.error = error
            }
        }

        semaphore.wait()

        if let thrownError = errorBox.error {
            throw thrownError
        }
    }

    func stop() {
        sessionQueue.sync {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    private func configureIfNeeded() throws {
        guard captureSession.inputs.isEmpty else { return }
        guard let device = AVCaptureDevice.devices().first(where: { $0.uniqueID == deviceUniqueID }) else {
            throw LocalCameraSessionError.deviceUnavailable
        }

        captureSession.beginConfiguration()

        if captureSession.canSetSessionPreset(.vga640x480) {
            captureSession.sessionPreset = .vga640x480
        } else if captureSession.canSetSessionPreset(.medium) {
            captureSession.sessionPreset = .medium
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw LocalCameraSessionError.unableToAddInput
        }
        captureSession.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard captureSession.canAddOutput(videoOutput) else {
            captureSession.commitConfiguration()
            throw LocalCameraSessionError.unableToAddOutput
        }
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.isVideoMirrored = false
        }

        captureSession.commitConfiguration()
    }
}

extension AVCaptureCameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        if targetSize.width > 0, targetSize.height > 0 {
            let scaleX = targetSize.width / extent.width
            let scaleY = targetSize.height / extent.height
            let scale = min(scaleX, scaleY)
            if scale > 0 {
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        sequence += 1
        let frame = CapturedFrame(
            sourceID: sourceID,
            providerType: providerType,
            image: cgImage,
            capturedAt: Date(),
            sequence: sequence,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height)
        )
        onFrame?(frame)
    }
}

private enum LocalCameraSessionError: LocalizedError {
    case deviceUnavailable
    case unableToAddInput
    case unableToAddOutput

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "The selected local camera is no longer available."
        case .unableToAddInput:
            return "The local camera input could not be added."
        case .unableToAddOutput:
            return "The local camera output could not be added."
        }
    }
}

private extension AVCaptureDevice {
    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}

private final class LocalCameraErrorBox {
    var error: Error?
}

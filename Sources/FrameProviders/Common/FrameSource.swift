import Foundation

struct FrameSource: Sendable, Hashable {
    let camera: CameraDefinition
    let configuredFPS: Double
    let frameWidth: Int
    let frameHeight: Int

    var signature: CameraConfigurationSignature {
        camera.configurationSignature(
            captureFPS: configuredFPS,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
    }
}

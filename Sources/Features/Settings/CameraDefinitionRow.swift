import SwiftUI

struct CameraDefinitionRow: View {
    let camera: CameraDefinition

    var body: some View {
        HStack(spacing: 8) {
            DSStatusBadge(
                title: camera.isEnabled ? "Enabled" : "Disabled",
                color: camera.isEnabled ? .green : .gray
            )

            DSStatusBadge(
                title: camera.providerType == .ffmpeg ? "RTSP Source" : camera.providerType == .webView ? "WebView Source" : "Local Camera",
                color: camera.providerType == .ffmpeg ? .blue : camera.providerType == .webView ? .indigo : .teal
            )

            if !camera.trimmedSceneName.isEmpty {
                DSStatusBadge(title: "OBS Scene Set", color: .purple)
            }

            DSStatusBadge(
                title: camera.isValidSourceConfiguration ? "Source Ready" : "Source Incomplete",
                color: camera.isValidSourceConfiguration ? .green : .orange
            )
        }
    }
}

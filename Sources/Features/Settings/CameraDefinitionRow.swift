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
                title: camera.hasValidStreamURL ? "RTSP Ready" : "Invalid URL",
                color: camera.hasValidStreamURL ? .blue : .orange
            )

            if !camera.trimmedSceneName.isEmpty {
                DSStatusBadge(title: "OBS Scene Set", color: .purple)
            }
        }
    }
}

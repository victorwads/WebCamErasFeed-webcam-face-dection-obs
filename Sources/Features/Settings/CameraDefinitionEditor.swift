import SwiftUI

struct CameraDefinitionEditor: View {
    @Binding var camera: CameraDefinition
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        DSFormField(title: "Name", text: $camera.name, prompt: "Desk Camera")
                        DSFormField(title: "OBS Scene Name", text: $camera.sceneName, prompt: "Desk Scene")
                        DSFormField(title: "RTSP Stream URL", text: $camera.streamURL, prompt: "rtsp://localhost:8554/camera_c300")
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        Toggle("Enabled", isOn: $camera.isEnabled)
                            .toggleStyle(.switch)
                        HStack {
                            Button {
                                onMoveUp()
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .disabled(!canMoveUp)

                            Button {
                                onMoveDown()
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .disabled(!canMoveDown)
                        }

                        Button("Remove", role: .destructive) {
                            onRemove()
                        }
                    }
                    .frame(width: 140)
                }

                CameraDefinitionRow(camera: camera)
            }
        }
    }
}

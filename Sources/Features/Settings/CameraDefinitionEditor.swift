import SwiftUI

struct CameraDefinitionEditor: View {
    @Binding var camera: CameraDefinition
    let localCameraDevices: [LocalCameraDevice]
    let localCameraAuthorizationStatus: LocalCameraAuthorizationStatus
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRefreshDevices: () -> Void
    let onRequestAccess: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        DSFormField(title: "Name", text: $camera.name, prompt: "Desk Camera")
                        DSFormField(title: "OBS Scene Name", text: $camera.sceneName, prompt: "Desk Scene")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Source Type")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Picker("Source Type", selection: $camera.sourceType) {
                                ForEach(CameraSourceType.allCases) { sourceType in
                                    Text(sourceType.displayName).tag(sourceType)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if camera.sourceType == .networkStream {
                            DSFormField(title: "RTSP Stream URL", text: $camera.streamURL, prompt: "rtsp://127.0.0.1:8554/camera_c300")
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Local Camera")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)

                                Picker(
                                    "Local Camera",
                                    selection: Binding(
                                        get: { camera.localDeviceUniqueID ?? "" },
                                        set: { camera.localDeviceUniqueID = $0.isEmpty ? nil : $0 }
                                    )
                                ) {
                                    Text("Select a camera").tag("")
                                    ForEach(localCameraDevices) { device in
                                        Text(device.localizedName).tag(device.id)
                                    }
                                }

                                HStack {
                                    Button("Refresh Devices") {
                                        onRefreshDevices()
                                    }

                                    if localCameraAuthorizationStatus != .authorized {
                                        Button("Grant Camera Access") {
                                            onRequestAccess()
                                        }
                                    }
                                }

                                Text("Permission: \(localCameraAuthorizationStatus.displayName)")
                                    .font(.footnote)
                                    .foregroundStyle(localCameraAuthorizationStatus == .authorized ? Color.secondary : Color.orange)

                                if let selectedID = camera.trimmedLocalDeviceUniqueID,
                                   !localCameraDevices.contains(where: { $0.id == selectedID }) {
                                    Text("The selected device is no longer available on this Mac.")
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
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

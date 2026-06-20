import SwiftUI

struct CameraDefinitionEditor: View {
    @Binding var camera: CameraDefinition
    let localCameraDevices: [LocalCameraDevice]
    let localCameraAuthorizationStatus: LocalCameraAuthorizationStatus
    let webViewStatus: WebViewWindowRuntimeStatus?
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRefreshDevices: () -> Void
    let onRequestAccess: () -> Void
    let onOpenWebViewWindow: () -> Void
    let onReloadWebViewWindow: () -> Void
    let onShowWebViewWindow: () -> Void
    let onHideWebViewWindow: () -> Void
    let onBringWebViewWindowToFront: () -> Void
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
                            Text("Provider Type")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Picker("Provider Type", selection: $camera.providerType) {
                                ForEach(FrameProviderType.allCases) { providerType in
                                    Text(providerType.displayName).tag(providerType)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        switch camera.providerType {
                        case .ffmpeg:
                            DSFormField(title: "RTSP Stream URL", text: $camera.streamURL, prompt: "rtsp://127.0.0.1:8554/camera_c300")

                        case .webView:
                            webViewSettings

                        case .localCamera:
                            localCameraSettings
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

    private var localCameraSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Camera")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Picker(
                "Local Camera",
                selection: Binding(
                    get: {
                        guard let localDeviceUniqueID = camera.localDeviceUniqueID,
                              localCameraDevices.contains(where: { $0.id == localDeviceUniqueID }) else {
                            return ""
                        }
                        return localDeviceUniqueID
                    },
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

    private var webViewSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSFormField(title: "WebRTC Page URL", text: $camera.streamURL, prompt: "http://127.0.0.1:1984/webrtc.html?src=camera_c300&media=video")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Window Width")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField(
                        "1280",
                        value: $camera.webViewWidth,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Window Height")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField(
                        "720",
                        value: $camera.webViewHeight,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                }
            }

            HStack {
                Button("Open Window") {
                    onOpenWebViewWindow()
                }
                Button("Reload") {
                    onReloadWebViewWindow()
                }
                Button("Show Window") {
                    onShowWebViewWindow()
                }
                Button("Hide Window") {
                    onHideWebViewWindow()
                }
                Button("Bring to Front") {
                    onBringWebViewWindowToFront()
                }
            }

            if let webViewStatus {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading Status: \(webViewStatus.navigationStatus)")
                    Text("Window Status: \(webViewStatus.windowStatus)")
                    if let loadedURL = webViewStatus.loadedURL {
                        Text("Loaded URL: \(loadedURL)")
                    }
                    if let error = webViewStatus.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text("Open the WebView window to preview the WebRTC stream and make it available for OBS Window Capture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

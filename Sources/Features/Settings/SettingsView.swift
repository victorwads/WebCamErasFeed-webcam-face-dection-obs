import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DSSectionHeader(
                    title: "Camera Director Settings",
                    subtitle: "Configure RTSP sources, capture timing, face detection and OBS integration."
                )

                DSCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cameras")
                                .font(.headline)
                            Spacer()
                            Button("Add Camera") {
                                viewModel.addCamera()
                            }
                        }

                        ForEach(Array(viewModel.cameras.enumerated()), id: \.element.id) { index, _ in
                            CameraDefinitionEditor(
                                camera: $viewModel.cameras[index],
                                localCameraDevices: viewModel.localCameraDevices,
                                localCameraAuthorizationStatus: viewModel.localCameraAuthorizationStatus,
                                onRemove: { viewModel.removeCamera(id: viewModel.cameras[index].id) },
                                onMoveUp: { viewModel.moveCameraUp(id: viewModel.cameras[index].id) },
                                onMoveDown: { viewModel.moveCameraDown(id: viewModel.cameras[index].id) },
                                onRefreshDevices: {
                                    Task {
                                        await viewModel.refreshLocalCameraDevices()
                                    }
                                },
                                onRequestAccess: {
                                    Task {
                                        await viewModel.requestLocalCameraPermission()
                                    }
                                },
                                canMoveUp: index > 0,
                                canMoveDown: index < viewModel.cameras.count - 1
                            )
                        }
                    }
                }

                CaptureIntervalSection(preferences: $viewModel.preferences)

                OBSSettingsSection(
                    preferences: $viewModel.preferences,
                    obsClient: appState.obsClient,
                    onConnect: { appState.connectOBS() },
                    onDisconnect: { appState.disconnectOBS() },
                    onRefreshScenes: { appState.refreshOBSScenes() }
                )

                HStack {
                    Toggle("Enable Face Detection", isOn: $viewModel.preferences.isFaceDetectionEnabled)
                        .toggleStyle(.switch)
                    Spacer()
                    Button("Save and Apply") {
                        Task {
                            await viewModel.apply()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }

                if let lastApplyMessage = viewModel.lastApplyMessage {
                    Text(lastApplyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .task {
            await viewModel.refreshLocalCameraDevices()
        }
    }
}

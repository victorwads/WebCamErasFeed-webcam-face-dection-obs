import SwiftUI

struct OBSSettingsSection: View {
    @Binding var preferences: AppPreferences
    @ObservedObject var obsClient: OBSClient
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onRefreshScenes: () -> Void
    let onProvisionScenes: () -> Void

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("OBS Integration")
                    .font(.headline)

                Toggle("Enable OBS Integration", isOn: $preferences.obsConfiguration.isEnabled)
                Toggle("Automatic Scene Switching", isOn: $preferences.obsConfiguration.automaticSceneSwitching)
                    .disabled(!preferences.obsConfiguration.isEnabled)

                HStack {
                    DSFormField(title: "Host", text: $preferences.obsConfiguration.host, prompt: "127.0.0.1")
                    TextField(
                        "4455",
                        value: $preferences.obsConfiguration.port,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }

                SecureField("Password", text: $preferences.obsConfiguration.password)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    DSStatusBadge(
                        title: obsClient.connectionState.label,
                        color: obsClient.connectionState == .connected ? .green : .gray
                    )

                    if let currentScene = obsClient.currentProgramSceneName {
                        Text("Current scene: \(currentScene)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = obsClient.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Connect") {
                        onConnect()
                    }
                    .disabled(!preferences.obsConfiguration.isEnabled)

                    Button("Disconnect") {
                        onDisconnect()
                    }

                    Button("Refresh Scenes") {
                        onRefreshScenes()
                    }
                    .disabled(obsClient.connectionState != .connected)

                    Button("Create / Sync OBS Scenes") {
                        onProvisionScenes()
                    }
                    .disabled(!preferences.obsConfiguration.isEnabled)
                }

                if !obsClient.availableScenes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available scenes")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        ForEach(obsClient.availableScenes) { scene in
                            Text(scene.name)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

import SwiftUI

struct MonitoringView: View {
    @ObservedObject var viewModel: MonitoringViewModel
    @ObservedObject var appState: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DSSectionHeader(
                    title: "Monitoring",
                    subtitle: "Static frame capture, Vision face detection and OBS selection feedback."
                )

                DSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            DSStatusBadge(
                                title: viewModel.isMonitoring ? "Monitoring" : "Idle",
                                color: viewModel.isMonitoring ? .green : .gray
                            )
                            if let scene = viewModel.lastRequestedOBSSceneName {
                                Text("Last OBS request: \(scene)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("Selection: \(viewModel.selectionReason)")
                            .font(.subheadline)

                        if let switchedAt = viewModel.lastOBSSceneSwitchAt {
                            Text("Last scene switch: \(switchedAt.formatted(date: .omitted, time: .standard))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if viewModel.orderedRuntimeStates().isEmpty {
                    DSEmptyState(
                        title: "No enabled cameras",
                        message: "Enable at least one source in Settings and click Save and Apply."
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.orderedRuntimeStates(), id: \.0.id) { camera, runtimeState in
                            CameraPreviewCard(
                                camera: camera,
                                runtimeState: runtimeState,
                                currentOBSSceneName: appState.obsClient.currentProgramSceneName,
                                onSwitchScene: { viewModel.switchToScene(for: camera) }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

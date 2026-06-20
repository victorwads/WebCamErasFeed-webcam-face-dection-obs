import SwiftUI

struct CameraPreviewCard: View {
    let camera: CameraDefinition
    let runtimeState: CameraRuntimeState
    let currentOBSSceneName: String?
    let onSwitchScene: () -> Void

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(camera.displayName)
                            .font(.headline)
                        Text(camera.trimmedSceneName.isEmpty ? "No OBS scene assigned" : camera.trimmedSceneName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if runtimeState.isSelected {
                        DSStatusBadge(title: "Selected", color: .green)
                    }
                }

                ZStack {
                    if let image = runtimeState.image {
                        GeometryReader { geometry in
                            ZStack {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                if let detectionResult = runtimeState.detectionResult,
                                   let imagePixelSize = runtimeState.imagePixelSize {
                                    FaceBoundingBoxOverlay(
                                        imagePixelSize: imagePixelSize,
                                        faces: detectionResult.faces
                                    )
                                }
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    } else {
                        DSEmptyState(
                            title: "No frame yet",
                            message: runtimeState.errorMessage ?? "Waiting for the first capture cycle."
                        )
                    }
                }
                .frame(height: 220)

                HStack {
                    DSStatusBadge(title: runtimeState.status.rawValue.capitalized, color: badgeColor)
                    if currentOBSSceneName == camera.trimmedSceneName, !camera.trimmedSceneName.isEmpty {
                        DSStatusBadge(title: "OBS Live", color: .blue)
                    }
                }

                FaceDetectionDetailsView(result: runtimeState.detectionResult)

                if let capturedAt = runtimeState.lastCapturedAt {
                    Text("Last frame: \(capturedAt.formatted(date: .omitted, time: .standard))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = runtimeState.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if !camera.trimmedSceneName.isEmpty {
                    Button("Switch OBS to This Scene") {
                        onSwitchScene()
                    }
                }
            }
        }
    }

    private var badgeColor: Color {
        switch runtimeState.status {
        case .idle:
            return .gray
        case .capturing:
            return .blue
        case .processing:
            return .orange
        case .error:
            return .red
        }
    }
}

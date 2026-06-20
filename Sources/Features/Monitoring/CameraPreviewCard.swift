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
                    if runtimeState.isReconnecting {
                        DSStatusBadge(title: "Reconnecting", color: .orange)
                    }
                }

                FaceDetectionDetailsView(result: runtimeState.detectionResult)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider: \(camera.sourceSummary)")
                    Text("Session: \(runtimeState.sessionModeLabel ?? "Unknown")")
                    if let providerState = runtimeState.providerState?.rawValue {
                        Text("Provider state: \(providerState)")
                    }
                    if let fps = runtimeState.configuredFPS {
                        Text("Configured rate: \(fps.formattedFPS)")
                    }
                    if let sequence = runtimeState.lastFrameSequence {
                        Text("Last frame sequence: \(sequence)")
                    }
                    if let age = runtimeState.lastFrameAgeDescription {
                        Text("Frame age: \(age)")
                    }
                    Text("Restarts: \(runtimeState.restartCount)")

                    if let pid = runtimeState.processIdentifier {
                        Text("FFmpeg PID: \(pid)")
                    }

                    if let usingVideoToolbox = runtimeState.usingVideoToolbox {
                        Text("VideoToolbox: \(usingVideoToolbox ? "Enabled" : "Disabled")")
                    }

                    if runtimeState.isUsingVideoToolboxFallback {
                        Text("Hardware decode fallback active")
                    }

                    if let diagnosticMessage = runtimeState.diagnosticMessage {
                        Text("Diagnostic: \(diagnosticMessage)")
                    }
                    if let navigationStatus = runtimeState.webViewNavigationStatus {
                        Text("WebView: \(navigationStatus)")
                    }
                    if let windowStatus = runtimeState.webViewWindowStatus {
                        Text("Window: \(windowStatus)")
                    }
                    if let captureStatus = runtimeState.screenCaptureStatus {
                        Text("ScreenCapture: \(captureStatus)")
                    }
                    if let loadedURL = runtimeState.loadedURL {
                        Text("Loaded URL: \(loadedURL)")
                            .lineLimit(2)
                    }
                    if runtimeState.screenCapturePermissionDenied {
                        Text("Grant Screen Recording permission in System Settings > Privacy & Security > Screen Recording.")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

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

                if camera.providerType == .webView {
                    Text("Use the Settings tab to bring the WebView window to the front or reload the stream.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var badgeColor: Color {
        switch runtimeState.status {
        case .idle:
            return .gray
        case .starting:
            return .mint
        case .capturing:
            return .blue
        case .processing:
            return .orange
        case .reconnecting:
            return .yellow
        case .stopped:
            return .gray
        case .error:
            return .red
        }
    }
}

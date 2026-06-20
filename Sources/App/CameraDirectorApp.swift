import SwiftUI

@main
struct CameraDirectorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 760)
        }
        .windowResizability(.contentSize)
    }
}

private struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            SettingsView(viewModel: appState.settingsViewModel, appState: appState)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }

            MonitoringView(viewModel: appState.monitoringViewModel, appState: appState)
                .tabItem {
                    Label("Monitoring", systemImage: "rectangle.grid.2x2")
                }
        }
        .padding()
    }
}

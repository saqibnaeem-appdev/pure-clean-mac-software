import SwiftUI

@main
struct PureCleanApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(appState)
        } label: {
            Image(systemName: "sparkles")
                .accessibilityLabel("PureClean")
        }
        .menuBarExtraStyle(.window)
    }
}

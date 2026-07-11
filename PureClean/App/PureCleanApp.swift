import SwiftUI

@main
struct PureCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppState.shared

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        Window("PureClean", id: "main") {
            MainWindowView()
                .environment(app)
                .frame(minWidth: 1020, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1150, height: 730)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(app)
        }

        MenuBarExtra(isInserted: Bindable(app.settings).showMenuBarIcon) {
            MenuBarContent()
                .environment(app)
        } label: {
            Image(systemName: "sparkles")
                .accessibilityLabel("PureClean")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Keeps PureClean alive in the menu bar when the dashboard window closes,
/// and brings the window back when the user clicks the Dock icon again.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.setActivationPolicy(.regular)
            AppState.shared.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}

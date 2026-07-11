import SwiftUI
import AppKit

/// Native menu shown from the menu bar sparkle. Quick status at a glance,
/// then one-click actions — the app stays alive here when the window closes.
struct MenuBarContent: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snap = app.monitor.snapshot

        // Plain Text rows render as disabled info lines in a native menu.
        Text("CPU \(snap.cpu.usage.percentFormatted)  ·  Memory \(snap.memory.free.bytesFormatted) free")
        Text("Storage \(snap.disk.available.bytesFormatted) available")

        Divider()

        Button("Open PureClean") {
            app.showMainWindow(openWindow: openWindow)
        }
        .keyboardShortcut("o")

        Button("Run Smart Scan") {
            app.showMainWindow(openWindow: openWindow)
            app.runSmartScan()
        }
        .keyboardShortcut("s")

        Button(app.memory.isFreeing ? "Freeing Memory…" : "Free Memory") {
            Task { await app.memory.freeMemory() }
        }
        .disabled(app.memory.isFreeing)

        Button("Show Trash (\(app.trash.totalSize.bytesFormatted))") {
            app.showMainWindow(openWindow: openWindow)
            app.route = .trash
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit PureClean") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

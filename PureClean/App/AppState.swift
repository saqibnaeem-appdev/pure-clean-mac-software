import SwiftUI

/// Composition root — owns every service and starts the background work.
/// Views receive it via `@Environment` and talk to focused managers,
/// keeping the MVVM boundaries clean.
@MainActor
@Observable
final class AppState {

    static let shared = AppState()

    let settings = AppSettings()
    let monitor = SystemMonitor()
    let scanner = ScanEngine()
    let memory = MemoryManager()
    let disk = DiskService()
    let trash = TrashService()
    let largeFiles = LargeFileFinder()
    let duplicates = DuplicateFinder()
    let uninstaller = AppUninstaller()
    let startup = StartupManager()
    let notifications = NotificationManager()
    let scheduler = ScheduleManager()
    let permissions = PermissionManager()

    /// Currently selected sidebar page.
    var route: Route = .dashboard

    /// The dashboard window, captured so the dock/menu-bar reopen paths can
    /// bring it back without spawning duplicates.
    weak var mainWindow: NSWindow?

    private var thresholdTimer: Timer?

    private init() {
        monitor.start()
        disk.refreshOverview()
        trash.startWatching()
        scheduler.start(scanner: scanner, notifications: notifications)
        permissions.refresh()

        // Threshold checks every 5 minutes — cheap, uses cached scan sizes.
        thresholdTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.notifications.checkThresholds(
                    snapshot: self.monitor.snapshot,
                    cacheSize: self.scanner.recoverableTotal)
            }
        }
    }

    /// Kicks off a Smart Scan and navigates to its page (used by the
    /// dashboard hero button and the menu bar quick action).
    func runSmartScan() {
        route = .smartScan
        guard !scanner.isScanning, !scanner.isCleaning else { return }
        startup.scan()
        scanner.smartScan(context: ScanContext(
            snapshot: monitor.snapshot,
            loginItemCount: startup.items.count))
    }

    /// Shows the dashboard window and gives the app a Dock presence.
    func showMainWindow(openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

import SwiftUI

/// Composition root — owns every manager and starts the background work.
/// Views receive it via `@EnvironmentObject` and talk to focused
/// view models / managers, keeping the MVVM boundaries clean.
@MainActor
@Observable
final class AppState {

    let stats = SystemStatsManager()
    let cleaner = CleanerManager()
    let memory = MemoryManager()
    let analyzer = DiskAnalyzerManager()
    let largeFiles = LargeFileFinder()
    let duplicates = DuplicateFinder()
    let uninstaller = AppUninstaller()
    let startup = StartupManager()
    let notifications = NotificationManager()
    let scheduler = ScheduleManager()
    let permissions = PermissionManager()

    private var thresholdTimer: Timer?

    init() {
        stats.start()
        scheduler.start(cleaner: cleaner, notifications: notifications)
        permissions.refresh()
        Task { await cleaner.scan() }

        // Threshold checks every 5 minutes — cheap, uses cached scan sizes.
        thresholdTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.notifications.checkThresholds(
                    snapshot: self.stats.snapshot,
                    cacheSize: self.cleaner.recoverableTotal)
            }
        }
    }
}

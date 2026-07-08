import Foundation
import Observation

/// Runs Smart Clean automatically on a daily/weekly/monthly cadence.
/// The check runs hourly while the app is in the menu bar; a clean only
/// fires when the chosen interval has elapsed since the last one.
@MainActor
@Observable
final class ScheduleManager {

    var schedule: CleanSchedule {
        didSet { UserDefaults.standard.set(schedule.rawValue, forKey: "cleanSchedule") }
    }

    private weak var cleaner: CleanerManager?
    private weak var notifications: NotificationManager?
    private var timer: Timer?

    init() {
        let raw = UserDefaults.standard.string(forKey: "cleanSchedule") ?? CleanSchedule.off.rawValue
        schedule = CleanSchedule(rawValue: raw) ?? .off
    }

    func start(cleaner: CleanerManager, notifications: NotificationManager) {
        self.cleaner = cleaner
        self.notifications = notifications
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runIfDue() }
        }
        Task { await runIfDue() }
    }

    var lastCleanDate: Date? {
        UserDefaults.standard.object(forKey: "lastCleanDate") as? Date
    }

    func runIfDue() async {
        guard let interval = schedule.interval, let cleaner else { return }
        let last = lastCleanDate ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval, !cleaner.isCleaning else { return }

        await cleaner.scan()
        // Scheduled cleans only touch the always-safe default categories.
        for index in cleaner.categories.indices {
            cleaner.categories[index].isSelected = cleaner.categories[index].defaultEnabled
        }
        let result = await cleaner.cleanSelected()
        if result.freedBytes > 0 {
            notifications?.notifyCleanFinished(freed: result.freedBytes)
        }
    }
}

import Foundation
import Observation

/// Runs the always-safe clean automatically on a daily/weekly/monthly
/// cadence. The check runs hourly while the app lives in the menu bar; a
/// clean only fires when the chosen interval has elapsed since the last one.
@MainActor
@Observable
final class ScheduleManager {

    var schedule: CleanSchedule {
        didSet { UserDefaults.standard.set(schedule.rawValue, forKey: "cleanSchedule") }
    }

    private weak var scanner: ScanEngine?
    private weak var notifications: NotificationManager?
    private var timer: Timer?

    init() {
        let raw = UserDefaults.standard.string(forKey: "cleanSchedule") ?? CleanSchedule.off.rawValue
        schedule = CleanSchedule(rawValue: raw) ?? .off
    }

    func start(scanner: ScanEngine, notifications: NotificationManager) {
        self.scanner = scanner
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
        guard let interval = schedule.interval, let scanner else { return }
        let last = lastCleanDate ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval,
              !scanner.isCleaning, !scanner.isScanning else { return }

        let result = await scanner.quickCleanSafe()
        if result.freedBytes > 0 {
            notifications?.notifyCleanFinished(freed: result.freedBytes)
        }
    }
}

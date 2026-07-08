import Foundation
import Observation
import UserNotifications

/// Local notifications for low storage, high memory pressure and oversized
/// cache. Permission is requested lazily, the first time it's needed.
@MainActor
@Observable
final class NotificationManager {

    var storageAlerts = UserDefaults.standard.object(forKey: "notif.storage") as? Bool ?? true {
        didSet { UserDefaults.standard.set(storageAlerts, forKey: "notif.storage") }
    }
    var memoryAlerts = UserDefaults.standard.object(forKey: "notif.memory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(memoryAlerts, forKey: "notif.memory") }
    }
    var cacheAlerts = UserDefaults.standard.object(forKey: "notif.cache") as? Bool ?? true {
        didSet { UserDefaults.standard.set(cacheAlerts, forKey: "notif.cache") }
    }

    /// Don't nag: at most one alert per topic per 6 hours.
    private var lastSent: [String: Date] = [:]

    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    func checkThresholds(snapshot: SystemSnapshot, cacheSize: Int64) {
        if storageAlerts, snapshot.diskTotal > 0,
           Double(snapshot.diskFree) / Double(snapshot.diskTotal) < 0.10 {
            send(id: "storage", title: "Storage running low",
                 body: "Only \(snapshot.diskFree.bytesFormatted) free. Run Smart Clean to recover space safely.")
        }
        if memoryAlerts, snapshot.memory.usedFraction > 0.90 {
            send(id: "memory", title: "Memory pressure is high",
                 body: "\(snapshot.memory.used.bytesFormatted) of \(snapshot.memory.total.bytesFormatted) in use. Try Free Memory.")
        }
        if cacheAlerts, cacheSize > 5_368_709_120 {
            send(id: "cache", title: "Caches exceed 5 GB",
                 body: "You can safely recover \(cacheSize.bytesFormatted) with Smart Clean.")
        }
    }

    func notifyCleanFinished(freed: Int64) {
        send(id: "clean-\(UUID().uuidString)", title: "Scheduled clean finished",
             body: "PureClean recovered \(freed.bytesFormatted) for you.", throttle: false)
    }

    private func send(id: String, title: String, body: String, throttle: Bool = true) {
        if throttle, let last = lastSent[id], Date().timeIntervalSince(last) < 6 * 3600 { return }
        lastSent[id] = Date()

        requestPermissionIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

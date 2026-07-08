import Foundation
import SwiftUI

/// Presents dashboard-ready values assembled from the stats and cleaner
/// managers. Pure formatting/derivation — no side effects.
@MainActor
struct DashboardViewModel {

    let snapshot: SystemSnapshot
    let cleaner: CleanerManager

    var storageUsedFraction: Double {
        snapshot.diskTotal > 0 ? Double(snapshot.diskUsed) / Double(snapshot.diskTotal) : 0
    }

    var recoverableText: String {
        let bytes = cleaner.recoverableSelected
        return bytes > 0
            ? "You can safely recover \(bytes.bytesFormatted)"
            : "Scanning for junk…"
    }

    func categorySize(_ id: String) -> Int64 {
        cleaner.categories.first { $0.id == id }?.scannedSize ?? 0
    }

    var cacheSize: Int64 { categorySize("user-cache") + categorySize("browser-cache") }
    var trashSize: Int64 { categorySize("trash") }
    var tempSize: Int64 { categorySize("temp") }

    var batteryText: String {
        guard snapshot.battery.hasBattery else { return "No battery" }
        var text = "\(snapshot.battery.percentage)%"
        if snapshot.battery.healthPercent > 0 {
            text += " · \(snapshot.battery.healthPercent)% health"
        }
        return text
    }

    var batteryDetail: String {
        guard snapshot.battery.hasBattery else { return "Desktop Mac" }
        return snapshot.battery.isCharging
            ? "Charging · \(snapshot.battery.cycleCount) cycles"
            : "\(snapshot.battery.cycleCount) cycles"
    }
}

import Foundation
import SwiftUI

// MARK: - Cleaning

/// A safe-to-clean category. Every path listed here is validated again by
/// `SafetyGuard` before any file operation — belt and braces.
struct CleanCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let detail: String
    /// Directories whose *contents* are cleaned (the directory itself stays).
    let contentRoots: [URL]
    /// Only files matching these extensions are touched (nil = everything).
    let allowedExtensions: Set<String>?
    /// Only files older than this many days are touched (nil = any age).
    let minimumAgeDays: Int?
    /// Whether the category is selected for Smart Clean by default.
    let defaultEnabled: Bool

    var scannedSize: Int64 = 0
    var isSelected: Bool = true

    init(
        id: String, name: String, icon: String, detail: String,
        contentRoots: [URL], allowedExtensions: Set<String>? = nil,
        minimumAgeDays: Int? = nil, defaultEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.detail = detail
        self.contentRoots = contentRoots
        self.allowedExtensions = allowedExtensions
        self.minimumAgeDays = minimumAgeDays
        self.defaultEnabled = defaultEnabled
        self.isSelected = defaultEnabled
    }
}

struct CleanResult {
    var freedBytes: Int64 = 0
    var removedItems: Int = 0
    var failedItems: Int = 0
}

// MARK: - Tools

struct LargeFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let modified: Date
}

struct DuplicateGroup: Identifiable, Hashable {
    let id: String            // content hash
    let files: [URL]
    let fileSize: Int64
    /// Space recovered if all but one copy are removed.
    var recoverable: Int64 { fileSize * Int64(max(0, files.count - 1)) }
}

struct InstalledApp: Identifiable, Hashable {
    var id: URL { bundleURL }
    let name: String
    let bundleURL: URL
    let bundleID: String
    var appSize: Int64 = 0
    var relatedFiles: [URL] = []
    var relatedSize: Int64 = 0
}

struct LoginItem: Identifiable, Hashable {
    var id: URL { plistURL }
    let label: String
    let plistURL: URL
    let programPath: String
    var isEnabled: Bool
}

struct FolderUsage: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let url: URL
    let size: Int64
    let colorIndex: Int
}

// MARK: - System stats

struct MemoryStats {
    var total: Int64 = 0
    var used: Int64 = 0
    var active: Int64 = 0
    var inactive: Int64 = 0
    var wired: Int64 = 0
    var compressed: Int64 = 0
    var free: Int64 { max(0, total - used) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct BatteryStats {
    var hasBattery = false
    var percentage: Int = 0
    var isCharging = false
    var cycleCount: Int = 0
    /// Current max capacity as a fraction of design capacity.
    var healthPercent: Int = 0
}

struct SystemSnapshot {
    var cpuUsage: Double = 0                 // 0…1
    var memory = MemoryStats()
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0
    var diskUsed: Int64 { max(0, diskTotal - diskFree) }
    var networkInPerSec: Int64 = 0
    var networkOutPerSec: Int64 = 0
    var battery = BatteryStats()
    var smartStatus: String = "—"
}

// MARK: - Settings

enum CleanSchedule: String, CaseIterable, Identifiable {
    case off, daily, weekly, monthly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
    var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .daily: 86_400
        case .weekly: 604_800
        case .monthly: 2_592_000
        }
    }
}

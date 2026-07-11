import Foundation
import SwiftUI

// MARK: - Navigation

/// Every page reachable from the sidebar. Raw values are stable identifiers
/// used for state restoration and deep links from the menu bar.
enum Route: String, CaseIterable, Identifiable, Hashable {
    case dashboard, smartScan, performance
    case storage, trash, largeFiles, duplicates
    case uninstaller, startup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .smartScan: "Smart Scan"
        case .performance: "Performance"
        case .storage: "Storage"
        case .trash: "Trash"
        case .largeFiles: "Large Files"
        case .duplicates: "Duplicates"
        case .uninstaller: "Uninstaller"
        case .startup: "Login Items"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .smartScan: "sparkles"
        case .performance: "waveform.path.ecg"
        case .storage: "internaldrive.fill"
        case .trash: "trash.fill"
        case .largeFiles: "doc.zipper"
        case .duplicates: "doc.on.doc.fill"
        case .uninstaller: "xmark.bin.fill"
        case .startup: "power"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard: .blue
        case .smartScan: .purple
        case .performance: .cyan
        case .storage: .indigo
        case .trash: .red
        case .largeFiles: .orange
        case .duplicates: .pink
        case .uninstaller: .teal
        case .startup: .green
        }
    }
}

// MARK: - Smart Scan

/// How dangerous a category is. `.safe` categories are ticked by default and
/// eligible for scheduled cleaning; `.review` categories start unticked.
enum ScanSafety {
    case safe
    case review
}

enum CategoryScanState: Equatable {
    case pending, scanning, done
}

struct ScanItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
}

/// One cleanable group produced by Smart Scan (caches, logs, leftovers…).
struct ScanCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let detail: String
    let safety: ScanSafety
    /// True when every item must be trashed via the user-reviewed path
    /// (leftovers, symlinks) rather than the allow-listed cache path.
    let userReviewed: Bool

    var items: [ScanItem] = []
    var size: Int64 = 0
    var fileCount: Int = 0
    var isSelected: Bool
    var state: CategoryScanState = .pending

    init(id: String, name: String, icon: String, detail: String,
         safety: ScanSafety, userReviewed: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.detail = detail
        self.safety = safety
        self.userReviewed = userReviewed
        self.isSelected = safety == .safe
    }
}

/// Live progress published by the scan engine while scanning or cleaning.
struct ScanProgress: Equatable {
    enum Phase: Equatable { case idle, scanning, results, cleaning, finished }

    var phase: Phase = .idle
    var fraction: Double = 0
    var filesScanned: Int = 0
    var bytesFound: Int64 = 0
    var currentCategory: String = ""
    var currentPath: String = ""
    var startedAt: Date?
    var etaSeconds: Int?
}

/// Non-destructive findings shown alongside the cleanable categories.
struct Insight: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var route: Route?
}

struct CleanResult: Equatable {
    var freedBytes: Int64 = 0
    var removedItems: Int = 0
    var failedItems: Int = 0
}

// MARK: - Storage

/// Accurate APFS volume numbers, matching what Finder reports.
/// `available` comes from `volumeAvailableCapacityForImportantUsage`
/// (free + purgeable), `free` is the strict statfs value.
struct DiskOverview: Equatable {
    var volumeName: String = "Macintosh HD"
    var fileSystem: String = "APFS"
    var total: Int64 = 0
    var free: Int64 = 0
    var available: Int64 = 0

    var purgeable: Int64 { max(0, available - free) }
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct FolderUsage: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let url: URL
    let size: Int64
    let colorIndex: Int
}

struct TrashItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let modified: Date
    let isDirectory: Bool
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

// MARK: - System monitoring

struct CPUStats: Equatable {
    var usage: Double = 0                    // 0…1 total
    var systemUsage: Double = 0
    var userUsage: Double = 0
    var perCore: [Double] = []
    var performanceCores: Int = 0
    var efficiencyCores: Int = 0
    var brand: String = ""
    var frequencyMHz: Int = 0                // 0 when the platform hides it
    var loadAverage: Double = 0
}

enum MemoryPressure: Int, Equatable {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct MemoryStats: Equatable {
    var total: Int64 = 0
    var used: Int64 = 0
    var appMemory: Int64 = 0
    var wired: Int64 = 0
    var compressed: Int64 = 0
    var cached: Int64 = 0
    var swapUsed: Int64 = 0
    var swapTotal: Int64 = 0
    var pressure: MemoryPressure = .normal

    var free: Int64 { max(0, total - used) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct DiskIOStats: Equatable {
    var readPerSec: Int64 = 0
    var writePerSec: Int64 = 0
}

struct NetworkStats: Equatable {
    var inPerSec: Int64 = 0
    var outPerSec: Int64 = 0
    var interfaceName: String = "—"
    var ipAddress: String = "—"
    var wifiSSID: String?
    var wifiRSSI: Int?
    var wifiTxRateMbps: Double?
}

struct GPUStats: Equatable {
    var available = false
    var name: String = "—"
    var utilization: Double?                 // 0…1 when the driver reports it
    var memoryUsed: Int64?
}

struct FanReading: Identifiable, Equatable {
    let id: Int
    let rpm: Int
}

/// Best-effort hardware sensors (SMC). Empty/nil when the platform
/// doesn't expose them — the UI says so instead of inventing numbers.
struct SensorStats: Equatable {
    var fans: [FanReading] = []
    var fanCount: Int = 0
    var cpuTemperature: Double?
    var gpuTemperature: Double?
}

struct BatteryStats: Equatable {
    var hasBattery = false
    var percentage: Int = 0
    var isCharging = false
    var isPluggedIn = false
    var cycleCount: Int = 0
    var healthPercent: Int = 0
    var designCapacitymAh: Int = 0
    var maxCapacitymAh: Int = 0
    var currentCapacitymAh: Int = 0
    var temperature: Double?                 // °C from the smart battery
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var powerSource: String = "—"
}

struct SystemSnapshot: Equatable {
    var cpu = CPUStats()
    var memory = MemoryStats()
    var disk = DiskOverview()
    var diskIO = DiskIOStats()
    var network = NetworkStats()
    var gpu = GPUStats()
    var sensors = SensorStats()
    var battery = BatteryStats()
    var uptime: TimeInterval = 0
    var osVersion: String = ""
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

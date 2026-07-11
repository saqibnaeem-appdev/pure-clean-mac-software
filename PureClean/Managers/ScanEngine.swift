import Foundation
import Observation
import AppKit

/// Context handed to the scanner so the insight cards can reference live
/// system state without the engine owning the monitor.
struct ScanContext {
    var snapshot = SystemSnapshot()
    var loginItemCount = 0
}

/// Orchestrates Smart Scan: measures every cleanable category with live
/// progress (file counter, byte counter, current path, ETA), builds system
/// insights, and performs the clean. Every removal goes through `SafetyGuard`.
@MainActor
@Observable
final class ScanEngine {

    var categories: [ScanCategory] = ScanEngine.buildCategories()
    private(set) var progress = ScanProgress()
    private(set) var insights: [Insight] = []
    private(set) var lastResult: CleanResult?
    private(set) var lastScanDate: Date?

    private var scanTask: Task<Void, Never>?

    var isScanning: Bool { progress.phase == .scanning }
    var isCleaning: Bool { progress.phase == .cleaning }
    var hasResults: Bool { progress.phase == .results || progress.phase == .finished }

    var recoverableSelected: Int64 {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }
    var recoverableTotal: Int64 {
        categories.reduce(0) { $0 + $1.size }
    }

    // MARK: - Category catalogue

    private static func buildCategories() -> [ScanCategory] {
        [
            ScanCategory(
                id: "user-cache", name: "System Junk", icon: "internaldrive",
                detail: "App and system caches in ~/Library/Caches — rebuilt automatically.",
                safety: .safe),
            ScanCategory(
                id: "browser-cache", name: "Browser Cache", icon: "safari",
                detail: "Safari, Chrome, Edge and Firefox caches. History, bookmarks and passwords are never touched.",
                safety: .safe),
            ScanCategory(
                id: "logs", name: "Log Files", icon: "doc.text",
                detail: "Application logs in ~/Library/Logs.",
                safety: .safe),
            ScanCategory(
                id: "crash-reports", name: "Crash Reports", icon: "exclamationmark.triangle",
                detail: "Diagnostic and crash reports that are no longer needed.",
                safety: .safe),
            ScanCategory(
                id: "temp", name: "Temporary Files", icon: "clock.arrow.circlepath",
                detail: "Your user temporary directory.",
                safety: .safe),
            ScanCategory(
                id: "quicklook", name: "Thumbnails", icon: "photo.on.rectangle",
                detail: "QuickLook previews and icon caches — macOS rebuilds them on demand.",
                safety: .safe),
            ScanCategory(
                id: "xcode-derived", name: "Xcode Derived Data", icon: "hammer",
                detail: "Build intermediates — regenerated on the next build.",
                safety: .safe),
            ScanCategory(
                id: "xcode-archives", name: "Xcode Archives", icon: "shippingbox",
                detail: "Old app archives. Enable only if you don't need past builds.",
                safety: .review),
            ScanCategory(
                id: "mail-cache", name: "Mail Attachments Cache", icon: "envelope",
                detail: "Downloaded attachment copies — Mail re-downloads them when opened. Needs Full Disk Access.",
                safety: .review),
            ScanCategory(
                id: "installers", name: "Old Installers", icon: "arrow.down.circle",
                detail: "DMG, PKG and XIP installers in Downloads older than 30 days.",
                safety: .review),
            ScanCategory(
                id: "leftovers", name: "App Leftovers", icon: "puzzlepiece.extension",
                detail: "Support files and preferences from apps that are no longer installed.",
                safety: .review, userReviewed: true),
            ScanCategory(
                id: "broken-symlinks", name: "Broken Symlinks", icon: "link.badge.plus",
                detail: "Links in your home folder that point to files that no longer exist.",
                safety: .review, userReviewed: true),
            ScanCategory(
                id: "trash", name: "Trash", icon: "trash",
                detail: "Everything currently in your Trash. Emptying is permanent — review it first.",
                safety: .review),
        ]
    }

    /// Content roots for the directory-based categories.
    nonisolated private static func roots(for id: String) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let caches = home.appendingPathComponent("Library/Caches")
        switch id {
        case "user-cache":
            return [caches]
        case "browser-cache":
            return [
                caches.appendingPathComponent("com.apple.Safari"),
                caches.appendingPathComponent("Google/Chrome"),
                caches.appendingPathComponent("Microsoft Edge"),
                caches.appendingPathComponent("Firefox"),
                caches.appendingPathComponent("Mozilla"),
                caches.appendingPathComponent("BraveSoftware"),
                caches.appendingPathComponent("com.operasoftware.Opera"),
            ]
        case "logs":
            return [home.appendingPathComponent("Library/Logs")]
        case "crash-reports":
            return [
                home.appendingPathComponent("Library/Logs/DiagnosticReports"),
                home.appendingPathComponent("Library/Application Support/CrashReporter"),
            ]
        case "temp":
            return [fm.temporaryDirectory]
        case "quicklook":
            return [
                caches.appendingPathComponent("com.apple.QuickLook.thumbnailcache"),
                caches.appendingPathComponent("com.apple.iconservices.store"),
            ]
        case "xcode-derived":
            return [home.appendingPathComponent("Library/Developer/Xcode/DerivedData")]
        case "xcode-archives":
            return [home.appendingPathComponent("Library/Developer/Xcode/Archives")]
        case "mail-cache":
            return [home.appendingPathComponent(
                "Library/Containers/com.apple.mail/Data/Library/Mail Downloads")]
        case "installers":
            return [home.appendingPathComponent("Downloads")]
        case "trash":
            return [home.appendingPathComponent(".Trash")]
        default:
            return []
        }
    }

    // MARK: - Smart Scan

    func smartScan(context: ScanContext) {
        guard !isScanning, !isCleaning else { return }

        var fresh = ScanProgress()
        fresh.phase = .scanning
        fresh.startedAt = Date()
        progress = fresh
        lastResult = nil
        insights = []
        for index in categories.indices {
            categories[index].items = []
            categories[index].size = 0
            categories[index].fileCount = 0
            categories[index].state = .pending
        }

        let plan = categories.map { (id: $0.id, userReviewed: $0.userReviewed) }
        scanTask = Task { [weak self] in
            let total = plan.count
            for (index, entry) in plan.enumerated() {
                guard let self, !Task.isCancelled else { return }

                if let categoryIndex = self.categories.firstIndex(where: { $0.id == entry.id }) {
                    self.categories[categoryIndex].state = .scanning
                    self.progress.currentCategory = self.categories[categoryIndex].name
                }

                let id = entry.id
                let baseFraction = Double(index) / Double(total)
                let result = await Task.detached(priority: .userInitiated) { [weak self] in
                    Self.measureCategory(id: id) { files, bytes, path in
                        Task { @MainActor [weak self] in
                            guard let self, self.isScanning else { return }
                            self.progress.filesScanned += files
                            self.progress.bytesFound += bytes
                            if !path.isEmpty { self.progress.currentPath = path }
                        }
                    }
                }.value

                guard !Task.isCancelled else { return }
                if let categoryIndex = self.categories.firstIndex(where: { $0.id == entry.id }) {
                    self.categories[categoryIndex].items = result.items
                    self.categories[categoryIndex].size = result.bytes
                    self.categories[categoryIndex].fileCount = result.files
                    self.categories[categoryIndex].state = .done
                }
                self.updateScanFraction(baseFraction + 1.0 / Double(total))
            }

            guard let self, !Task.isCancelled else { return }
            self.insights = Self.buildInsights(
                context: context, categories: self.categories)
            self.lastScanDate = Date()
            self.progress.phase = .results
            self.progress.fraction = 1
            self.progress.currentPath = ""
            self.progress.etaSeconds = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        progress = ScanProgress()
        for index in categories.indices where categories[index].state == .scanning {
            categories[index].state = .pending
        }
    }

    /// Returns to the idle state so a new scan can start fresh.
    func reset() {
        progress = ScanProgress()
        lastResult = nil
    }

    private func updateScanFraction(_ fraction: Double) {
        progress.fraction = min(1, fraction)
        if let started = progress.startedAt, fraction > 0.08 {
            let elapsed = Date().timeIntervalSince(started)
            let remaining = elapsed * (1 - fraction) / fraction
            progress.etaSeconds = max(0, Int(remaining.rounded()))
        }
    }

    // MARK: - Measurement (background)

    private struct CategoryResult {
        var items: [ScanItem] = []
        var bytes: Int64 = 0
        var files: Int = 0
    }

    /// files/bytes deltas + the path currently being measured. Called from a
    /// background thread; throttled by the caller's clock below.
    private typealias ProgressSink = (Int, Int64, String) -> Void

    nonisolated private static func measureCategory(
        id: String, sink: @escaping ProgressSink) -> CategoryResult {
        switch id {
        case "leftovers":
            return findLeftovers(sink: sink)
        case "broken-symlinks":
            return findBrokenSymlinks(sink: sink)
        default:
            return measureRoots(id: id, sink: sink)
        }
    }

    nonisolated private static func measureRoots(
        id: String, sink: @escaping ProgressSink) -> CategoryResult {
        let fm = FileManager.default
        var result = CategoryResult()
        let installerExtensions: Set<String>? = id == "installers"
            ? SafetyGuard.installerExtensions : nil
        let minimumAgeDays: Int? = id == "installers" ? 30 : nil

        for root in roots(for: id) {
            guard let children = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: id == "trash" ? [] : [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                if child.lastPathComponent == ".DS_Store" { continue }
                if let extensions = installerExtensions,
                   !extensions.contains(child.pathExtension.lowercased()) { continue }
                if let minAge = minimumAgeDays {
                    let modified = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    guard Date().timeIntervalSince(modified) / 86_400 >= Double(minAge) else { continue }
                }

                let measured = measureItem(at: child, sink: sink)
                result.items.append(ScanItem(url: child, size: measured.bytes))
                result.bytes += measured.bytes
                result.files += measured.files
            }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    /// Size + file count of one item, streaming progress as it walks.
    nonisolated private static func measureItem(
        at url: URL, sink: @escaping ProgressSink) -> (bytes: Int64, files: Int) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .totalFileSizeKey, .fileSizeKey, .isRegularFileKey,
        ]
        let values = try? url.resourceValues(forKeys: Set(keys + [.isDirectoryKey]))

        guard values?.isDirectory == true else {
            let size = Int64(values?.totalFileAllocatedSize
                             ?? values?.fileAllocatedSize
                             ?? values?.totalFileSize
                             ?? values?.fileSize ?? 0)
            sink(1, size, url.path)
            return (size, 1)
        }

        var bytes: Int64 = 0
        var files = 0
        var pendingFiles = 0
        var pendingBytes: Int64 = 0
        var lastFlush = Date()

        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [], errorHandler: { _, _ in true }) else { return (0, 0) }

        for case let fileURL as URL in enumerator {
            guard let fileValues = try? fileURL.resourceValues(forKeys: Set(keys)),
                  fileValues.isRegularFile == true else { continue }
            let size = Int64(fileValues.totalFileAllocatedSize
                             ?? fileValues.fileAllocatedSize
                             ?? fileValues.totalFileSize
                             ?? fileValues.fileSize ?? 0)
            bytes += size
            files += 1
            pendingBytes += size
            pendingFiles += 1

            let now = Date()
            if now.timeIntervalSince(lastFlush) > 0.05 {
                sink(pendingFiles, pendingBytes, fileURL.path)
                pendingFiles = 0
                pendingBytes = 0
                lastFlush = now
            }
        }
        if pendingFiles > 0 || pendingBytes > 0 {
            sink(pendingFiles, pendingBytes, url.path)
        }
        return (bytes, files)
    }

    // MARK: - Leftover + symlink finders

    /// Bundle-ID-named folders in Library whose app is gone. Conservative:
    /// requires a bundle-ID shape, skips Apple/our own, and only reports
    /// entries untouched for 30+ days.
    nonisolated private static func findLeftovers(sink: @escaping ProgressSink) -> CategoryResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var result = CategoryResult()

        var installed = Set<String>()
        for root in [URL(fileURLWithPath: "/Applications"),
                     URL(fileURLWithPath: "/System/Applications"),
                     home.appendingPathComponent("Applications")] {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            else { continue }
            for app in children where app.pathExtension == "app" {
                if let id = Bundle(url: app)?.bundleIdentifier {
                    installed.insert(id.lowercased())
                }
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { installed.insert(id.lowercased()) }
        }
        let ownID = (Bundle.main.bundleIdentifier ?? "com.awsnextgenit.PureClean").lowercased()
        installed.insert(ownID)

        let bundleIDPattern = try? NSRegularExpression(
            pattern: "^[a-z0-9-]+(\\.[a-z0-9_-]+){2,}$", options: [.caseInsensitive])

        func isOrphanedBundleID(_ name: String) -> Bool {
            let lower = name.lowercased()
            guard !lower.hasPrefix("com.apple."), !lower.hasPrefix("group."),
                  lower != ownID, !installed.contains(lower) else { return false }
            let range = NSRange(name.startIndex..., in: name)
            return bundleIDPattern?.firstMatch(in: name, range: range) != nil
        }

        let parents = [
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Caches"),
        ]
        for parent in parents {
            guard let children = try? fm.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for child in children {
                guard isOrphanedBundleID(child.lastPathComponent) else { continue }
                let modified = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                guard Date().timeIntervalSince(modified) > 30 * 86_400 else { continue }
                let measured = measureItem(at: child, sink: sink)
                result.items.append(ScanItem(url: child, size: measured.bytes))
                result.bytes += measured.bytes
                result.files += measured.files
            }
        }

        // Orphaned preference plists.
        let prefs = home.appendingPathComponent("Library/Preferences")
        if let plists = try? fm.contentsOfDirectory(
            at: prefs, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            for plist in plists where plist.pathExtension == "plist" {
                let base = plist.deletingPathExtension().lastPathComponent
                guard isOrphanedBundleID(base) else { continue }
                let size = Int64((try? plist.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                    .totalFileAllocatedSize ?? 0)
                result.items.append(ScanItem(url: plist, size: size))
                result.bytes += size
                result.files += 1
                sink(1, size, plist.path)
            }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    /// Dangling symlinks in the visible home tree (depth-limited).
    nonisolated private static func findBrokenSymlinks(sink: @escaping ProgressSink) -> CategoryResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var result = CategoryResult()

        guard let enumerator = fm.enumerator(
            at: home,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }) else { return result }

        for case let url as URL in enumerator {
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            if url.lastPathComponent == "Library" && enumerator.level == 1 {
                enumerator.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
            else { continue }
            let destination = url.resolvingSymlinksInPath()
            if !fm.fileExists(atPath: destination.path) {
                result.items.append(ScanItem(url: url, size: 0))
                result.files += 1
                sink(1, 0, url.path)
                if result.items.count >= 200 { break }
            }
        }
        return result
    }

    // MARK: - Insights

    nonisolated private static func buildInsights(
        context: ScanContext, categories: [ScanCategory]) -> [Insight] {
        var insights: [Insight] = []
        let snap = context.snapshot

        if snap.disk.total > 0 {
            let freeFraction = Double(snap.disk.available) / Double(snap.disk.total)
            insights.append(Insight(
                id: "disk",
                icon: "internaldrive",
                tint: freeFraction < 0.10 ? .red : freeFraction < 0.2 ? .orange : .green,
                title: "\(snap.disk.available.bytesFormatted) available",
                detail: snap.disk.purgeable > 0
                    ? "Includes \(snap.disk.purgeable.bytesFormatted) purgeable space macOS frees on demand."
                    : "of \(snap.disk.total.bytesFormatted) total storage.",
                route: .storage))
        }

        insights.append(Insight(
            id: "memory",
            icon: "memorychip",
            tint: snap.memory.pressure.color,
            title: "Memory pressure \(snap.memory.pressure.label.lowercased())",
            detail: "\(snap.memory.used.bytesFormatted) of \(snap.memory.total.bytesFormatted) in use, \(snap.memory.cached.bytesFormatted) cached files.",
            route: .performance))

        insights.append(Insight(
            id: "cpu",
            icon: "cpu",
            tint: snap.cpu.usage > 0.8 ? .orange : .cyan,
            title: "CPU at \(snap.cpu.usage.percentFormatted)",
            detail: "Load average \(String(format: "%.2f", snap.cpu.loadAverage)) across \(snap.cpu.perCore.count) cores.",
            route: .performance))

        if context.loginItemCount > 0 {
            insights.append(Insight(
                id: "login-items",
                icon: "power",
                tint: .green,
                title: "\(context.loginItemCount) launch agent\(context.loginItemCount == 1 ? "" : "s") at login",
                detail: "Review what starts automatically when you sign in.",
                route: .startup))
        }

        let oldDownloads = measureOldDownloads()
        if oldDownloads.bytes > 100_000_000 {
            insights.append(Insight(
                id: "downloads",
                icon: "arrow.down.circle",
                tint: .orange,
                title: "\(oldDownloads.bytes.bytesFormatted) of old downloads",
                detail: "\(oldDownloads.count) items in Downloads untouched for 90+ days. Review them in Large Files.",
                route: .largeFiles))
        }

        if snap.battery.hasBattery, snap.battery.healthPercent > 0, snap.battery.healthPercent < 80 {
            insights.append(Insight(
                id: "battery",
                icon: "battery.50percent",
                tint: .orange,
                title: "Battery health at \(snap.battery.healthPercent)%",
                detail: "\(snap.battery.cycleCount) charge cycles. Consider a battery service when below 80%.",
                route: .performance))
        }
        return insights
    }

    nonisolated private static func measureOldDownloads() -> (bytes: Int64, count: Int) {
        let fm = FileManager.default
        let downloads = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard let children = try? fm.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]) else { return (0, 0) }

        var bytes: Int64 = 0
        var count = 0
        for child in children {
            let values = try? child.resourceValues(
                forKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey])
            let modified = values?.contentModificationDate ?? .distantPast
            guard Date().timeIntervalSince(modified) > 90 * 86_400 else { continue }
            bytes += Int64(values?.totalFileAllocatedSize ?? 0)
            count += 1
        }
        return (bytes, count)
    }

    // MARK: - Clean

    /// Cleans every selected category. Items are moved to the Trash whenever
    /// possible so the user can restore them.
    func clean() async -> CleanResult {
        guard !isCleaning, !isScanning else { return lastResult ?? CleanResult() }
        progress.phase = .cleaning
        progress.fraction = 0
        progress.currentPath = ""

        struct Doomed { let url: URL; let size: Int64; let reviewed: Bool; let categoryID: String }
        let doomed: [Doomed] = categories
            .filter { $0.isSelected && !$0.items.isEmpty }
            .flatMap { category in
                category.items.map {
                    Doomed(url: $0.url, size: $0.size,
                           reviewed: category.userReviewed, categoryID: category.id)
                }
            }

        var result = CleanResult()
        var cleanedURLs = Set<URL>()
        for (index, item) in doomed.enumerated() {
            progress.currentPath = item.url.path
            do {
                try await Task.detached(priority: .utility) {
                    try SafetyGuard.trash(item.url, userReviewed: item.reviewed)
                }.value
                result.freedBytes += item.size
                result.removedItems += 1
                cleanedURLs.insert(item.url)
            } catch {
                result.failedItems += 1
            }
            progress.fraction = Double(index + 1) / Double(max(1, doomed.count))
        }

        for index in categories.indices {
            let remaining = categories[index].items.filter { !cleanedURLs.contains($0.url) }
            categories[index].items = remaining
            categories[index].size = remaining.reduce(0) { $0 + $1.size }
        }

        lastResult = result
        UserDefaults.standard.set(Date(), forKey: "lastCleanDate")
        progress.phase = .finished
        progress.currentPath = ""
        return result
    }

    /// Scheduled/menu-bar clean: scans and cleans only the always-safe
    /// categories, without touching the UI state machine.
    func quickCleanSafe() async -> CleanResult {
        guard progress.phase == .idle || hasResults else { return CleanResult() }

        let safeIDs = categories.filter { $0.safety == .safe }.map(\.id)
        var result = CleanResult()
        for id in safeIDs {
            let measured = await Task.detached(priority: .utility) {
                Self.measureCategory(id: id) { _, _, _ in }
            }.value
            for item in measured.items {
                do {
                    try await Task.detached(priority: .utility) {
                        try SafetyGuard.trash(item.url)
                    }.value
                    result.freedBytes += item.size
                    result.removedItems += 1
                } catch {
                    result.failedItems += 1
                }
            }
        }
        UserDefaults.standard.set(Date(), forKey: "lastCleanDate")
        return result
    }

    // MARK: - Maintenance

    /// Flushes the DNS cache (admin prompt explains why).
    nonisolated func flushDNS() -> Bool {
        ShellRunner.runPrivileged("dscacheutil -flushcache; killall -HUP mDNSResponder")
    }
}

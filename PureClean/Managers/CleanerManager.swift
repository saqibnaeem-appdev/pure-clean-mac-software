import Foundation
import Observation

/// Builds the catalogue of safe-to-clean categories, scans their sizes and
/// performs the actual clean. Every removal goes through `SafetyGuard`.
@MainActor
@Observable
final class CleanerManager {

    var categories: [CleanCategory] = []
    private(set) var isScanning = false
    private(set) var isCleaning = false
    private(set) var progress: Double = 0
    private(set) var lastResult: CleanResult?

    /// Total recoverable bytes across the currently selected categories.
    var recoverableSelected: Int64 {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.scannedSize }
    }
    var recoverableTotal: Int64 {
        categories.reduce(0) { $0 + $1.scannedSize }
    }

    init() {
        categories = Self.buildCategories()
    }

    // MARK: - Category catalogue

    private static func buildCategories() -> [CleanCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let caches = home.appendingPathComponent("Library/Caches")

        return [
            CleanCategory(
                id: "user-cache", name: "User & App Cache", icon: "internaldrive",
                detail: "App caches in ~/Library/Caches — apps rebuild these automatically.",
                contentRoots: [caches]),
            CleanCategory(
                id: "browser-cache", name: "Browser Cache", icon: "safari",
                detail: "Safari, Chrome, Edge and Firefox caches. Never touches history, bookmarks or passwords.",
                contentRoots: [
                    caches.appendingPathComponent("com.apple.Safari"),
                    caches.appendingPathComponent("Google/Chrome"),
                    caches.appendingPathComponent("Microsoft Edge"),
                    caches.appendingPathComponent("Firefox"),
                    caches.appendingPathComponent("Mozilla"),
                ]),
            CleanCategory(
                id: "xcode-derived", name: "Xcode DerivedData", icon: "hammer",
                detail: "Build intermediates — Xcode regenerates them on the next build.",
                contentRoots: [home.appendingPathComponent("Library/Developer/Xcode/DerivedData")]),
            CleanCategory(
                id: "xcode-archives", name: "Xcode Archives", icon: "shippingbox",
                detail: "Old app archives. Off by default — enable only if you don't need past builds.",
                contentRoots: [home.appendingPathComponent("Library/Developer/Xcode/Archives")],
                defaultEnabled: false),
            CleanCategory(
                id: "logs", name: "Logs", icon: "doc.text",
                detail: "Application log files in ~/Library/Logs.",
                contentRoots: [home.appendingPathComponent("Library/Logs")]),
            CleanCategory(
                id: "crash-reports", name: "Crash Reports", icon: "exclamationmark.triangle",
                detail: "Diagnostic and crash reports already sent or no longer needed.",
                contentRoots: [
                    home.appendingPathComponent("Library/Logs/DiagnosticReports"),
                    home.appendingPathComponent("Library/Application Support/CrashReporter"),
                ]),
            CleanCategory(
                id: "temp", name: "Temporary Files", icon: "clock.arrow.circlepath",
                detail: "Your user temporary directory.",
                contentRoots: [FileManager.default.temporaryDirectory]),
            CleanCategory(
                id: "quicklook", name: "QuickLook & Thumbnails", icon: "photo.on.rectangle",
                detail: "Preview thumbnails — macOS rebuilds them on demand.",
                contentRoots: [
                    caches.appendingPathComponent("com.apple.QuickLook.thumbnailcache"),
                    caches.appendingPathComponent("com.apple.iconservices.store"),
                ]),
            CleanCategory(
                id: "trash", name: "Trash", icon: "trash",
                detail: "Empties your Trash. This is the only permanent step — review it first!",
                contentRoots: [home.appendingPathComponent(".Trash")],
                defaultEnabled: false),
            CleanCategory(
                id: "installers", name: "Old Installers", icon: "arrow.down.circle",
                detail: "DMG/PKG installers in Downloads older than 30 days. Off by default.",
                contentRoots: [home.appendingPathComponent("Downloads")],
                allowedExtensions: SafetyGuard.installerExtensions,
                minimumAgeDays: 30,
                defaultEnabled: false),
        ]
    }

    // MARK: - Scan

    /// Computes the size of every category off the main thread.
    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        var updated = categories
        await withTaskGroup(of: (Int, Int64).self) { group in
            for (index, category) in updated.enumerated() {
                group.addTask {
                    let size = Self.measure(category)
                    return (index, size)
                }
            }
            for await (index, size) in group {
                updated[index].scannedSize = size
                let snapshot = updated
                await MainActor.run { [weak self] in self?.categories = snapshot }
            }
        }
    }

    nonisolated private static func measure(_ category: CleanCategory) -> Int64 {
        var total: Int64 = 0
        for url in candidateItems(in: category) {
            total += FileManager.default.itemSize(at: url)
        }
        return total
    }

    /// Lists top-level items in a category's roots that pass its filters.
    nonisolated private static func candidateItems(in category: CleanCategory) -> [URL] {
        let fm = FileManager.default
        var items: [URL] = []
        for root in category.contentRoots {
            guard let children = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                if let extensions = category.allowedExtensions,
                   !extensions.contains(child.pathExtension.lowercased()) { continue }
                if let minAge = category.minimumAgeDays {
                    let modified = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    let age = Date().timeIntervalSince(modified) / 86_400
                    guard age >= Double(minAge) else { continue }
                }
                items.append(child)
            }
        }
        return items
    }

    // MARK: - Clean

    /// Cleans all selected categories. Items are moved to the Trash whenever
    /// possible so users can restore them; unrecoverable cache files inside
    /// guard-approved roots are removed directly as a fallback.
    func cleanSelected() async -> CleanResult {
        guard !isCleaning else { return lastResult ?? CleanResult() }
        isCleaning = true
        progress = 0
        defer { isCleaning = false }

        let selected = categories.filter { $0.isSelected && $0.scannedSize > 0 }
        var result = CleanResult()
        let allItems: [(URL, Int64)] = selected.flatMap { category in
            Self.candidateItems(in: category).map { url in
                (url, FileManager.default.itemSize(at: url))
            }
        }

        for (index, item) in allItems.enumerated() {
            let (url, size) = item
            do {
                try await Task.detached(priority: .utility) {
                    try SafetyGuard.trash(url)
                }.value
                result.freedBytes += size
                result.removedItems += 1
            } catch {
                result.failedItems += 1
            }
            progress = Double(index + 1) / Double(max(1, allItems.count))
        }

        lastResult = result
        UserDefaults.standard.set(Date(), forKey: "lastCleanDate")
        await scan()
        return result
    }

    // MARK: - Maintenance actions

    /// Flushes the DNS cache. Explains itself via the system password prompt.
    nonisolated func flushDNS() -> Bool {
        ShellRunner.runPrivileged("dscacheutil -flushcache; killall -HUP mDNSResponder")
    }
}

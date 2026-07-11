import Foundation
import Observation

/// Accurate storage numbers and a read-only folder breakdown.
///
/// The overview uses `URLResourceValues` on the boot volume, which is the
/// same source Finder and System Settings read: `volumeTotalCapacity`,
/// the strict `volumeAvailableCapacity`, and
/// `volumeAvailableCapacityForImportantUsage` (free + purgeable on APFS).
@MainActor
@Observable
final class DiskService {

    private(set) var overview = DiskOverview()
    private(set) var usages: [FolderUsage] = []
    private(set) var isScanning = false
    private(set) var lastScanDate: Date?

    func refreshOverview() {
        overview = Self.readOverview()
    }

    nonisolated static func readOverview() -> DiskOverview {
        var overview = DiskOverview()
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
            .volumeTypeNameKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return overview }
        overview.total = Int64(values.volumeTotalCapacity ?? 0)
        overview.free = Int64(values.volumeAvailableCapacity ?? 0)
        overview.available = values.volumeAvailableCapacityForImportantUsage
            ?? overview.free
        // `important usage` can never be less than the strict free value.
        overview.available = max(overview.available, overview.free)
        overview.volumeName = values.volumeName ?? "Macintosh HD"
        overview.fileSystem = values.volumeTypeName ?? "APFS"
        return overview
    }

    /// Measures the folders that typically dominate a Mac. Sizes stream in
    /// one by one so the UI fills progressively instead of freezing.
    func scanFolders() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let targets: [(String, URL)] = [
            ("Applications", URL(fileURLWithPath: "/Applications")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Desktop", home.appendingPathComponent("Desktop")),
            ("Movies", home.appendingPathComponent("Movies")),
            ("Music", home.appendingPathComponent("Music")),
            ("Pictures", home.appendingPathComponent("Pictures")),
            ("Library", home.appendingPathComponent("Library")),
            ("Developer", home.appendingPathComponent("Library/Developer")),
        ]

        var results: [FolderUsage] = []
        for (index, target) in targets.enumerated() {
            let (name, url) = target
            let size = await Task.detached(priority: .utility) {
                FileManager.default.directorySize(at: url)
            }.value
            guard size > 0 else { continue }
            results.append(FolderUsage(name: name, url: url, size: size, colorIndex: index))
            usages = results.sorted { $0.size > $1.size }
        }
    }
}

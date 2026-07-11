import Foundation
import Observation
import AppKit

/// Accurate, live Trash accounting plus a safe "Empty Trash".
///
/// The size covers the user Trash (`~/.Trash`) *and* the per-volume
/// `.Trashes/<uid>` folders on mounted disks — the same set Finder empties.
/// A kernel file-system watcher on `~/.Trash` keeps the numbers live.
@MainActor
@Observable
final class TrashService {

    private(set) var totalSize: Int64 = 0
    private(set) var itemCount = 0
    /// Top-level items in the user Trash, largest first (for the preview).
    private(set) var items: [TrashItem] = []
    private(set) var isRefreshing = false
    private(set) var isEmptying = false
    private(set) var lastEmptied: Date?
    /// True when macOS refused to let us read ~/.Trash (needs Full Disk
    /// Access). The UI must say so instead of showing a fake zero.
    private(set) var needsFullDiskAccess = false

    private var watcher: DispatchSourceFileSystemObject?
    private var refreshTask: Task<Void, Never>?

    private var userTrash: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    /// All trash folders Finder would empty.
    nonisolated private static func trashLocations() -> [URL] {
        let fm = FileManager.default
        var locations = [fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")]
        let uid = getuid()
        if let volumes = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) {
            for volume in volumes {
                let trashes = volume.appendingPathComponent(".Trashes/\(uid)")
                if fm.fileExists(atPath: trashes.path) {
                    locations.append(trashes)
                }
            }
        }
        return locations
    }

    // MARK: - Watching

    func startWatching() {
        guard watcher == nil else { return }
        refresh()

        let descriptor = open(userTrash.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main)
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    // MARK: - Measuring

    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            let measured = await Task.detached(priority: .userInitiated) {
                Self.measure()
            }.value
            guard let self else { return }
            self.totalSize = measured.size
            self.itemCount = measured.count
            self.items = measured.top
            self.needsFullDiskAccess = measured.accessDenied
            self.isRefreshing = false
            self.refreshTask = nil
        }
    }

    nonisolated private static func measure()
        -> (size: Int64, count: Int, top: [TrashItem], accessDenied: Bool) {
        let fm = FileManager.default
        var total: Int64 = 0
        var count = 0
        var top: [TrashItem] = []
        var accessDenied = false

        for (index, location) in trashLocations().enumerated() {
            guard let children = try? fm.contentsOfDirectory(
                at: location,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: []) else {
                // The folder exists but macOS refused to open it — that's the
                // TCC gate on the user Trash, not an empty Trash.
                if index == 0, fm.fileExists(atPath: location.path) {
                    accessDenied = true
                }
                continue
            }
            for child in children where child.lastPathComponent != ".DS_Store" {
                let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let size = fm.itemSize(at: child)
                total += size
                count += 1
                // Only the user Trash is previewed item-by-item.
                if index == 0 {
                    top.append(TrashItem(
                        url: child,
                        size: size,
                        modified: values?.contentModificationDate ?? .distantPast,
                        isDirectory: values?.isDirectory ?? false))
                }
            }
        }
        top.sort { $0.size > $1.size }
        return (total, count, top, accessDenied)
    }

    // MARK: - Actions

    /// Permanently removes everything in the Trash. Only called after the
    /// user has seen the item preview and confirmed.
    func empty() async -> CleanResult {
        guard !isEmptying else { return CleanResult() }
        isEmptying = true
        defer { isEmptying = false }

        let expectedBytes = totalSize
        let result = await Task.detached(priority: .userInitiated) { () -> CleanResult in
            let fm = FileManager.default
            var result = CleanResult()
            for location in Self.trashLocations() {
                guard let children = try? fm.contentsOfDirectory(
                    at: location, includingPropertiesForKeys: nil) else { continue }
                for child in children {
                    do {
                        try fm.removeItem(at: child)
                        result.removedItems += 1
                    } catch {
                        result.failedItems += 1
                    }
                }
            }
            return result
        }.value

        var final = result
        if final.failedItems == 0 { final.freedBytes = expectedBytes }
        lastEmptied = Date()
        refresh()
        return final
    }

    func revealInFinder() {
        let url = userTrash
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Restores one item from the user Trash back to a user-chosen location.
    func putBack(_ item: TrashItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.url.lastPathComponent
        panel.prompt = "Restore"
        panel.message = "Choose where to restore \(item.url.lastPathComponent)."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.moveItem(at: item.url, to: destination)
        refresh()
    }
}

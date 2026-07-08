import Foundation
import Observation

/// Finds files above a size threshold for the user to review.
/// Finding is read-only; deleting always trashes (restorable) and only
/// ever acts on files the user explicitly ticked.
@MainActor
@Observable
final class LargeFileFinder {

    enum Threshold: Int64, CaseIterable, Identifiable {
        case mb500 = 524_288_000
        case gb1 = 1_073_741_824
        case gb5 = 5_368_709_120
        var id: Int64 { rawValue }
        var label: String {
            switch self {
            case .mb500: "500 MB"
            case .gb1: "1 GB"
            case .gb5: "5 GB"
            }
        }
    }

    var threshold: Threshold = .gb1
    private(set) var files: [LargeFile] = []
    private(set) var isScanning = false
    var selection = Set<URL>()

    var selectedBytes: Int64 {
        files.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        files = []
        selection = []
        defer { isScanning = false }

        let limit = threshold.rawValue
        let home = FileManager.default.homeDirectoryForCurrentUser
        let found = await Task.detached(priority: .userInitiated) { () -> [LargeFile] in
            var results: [LargeFile] = []
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey, .contentModificationDateKey]
            guard let enumerator = FileManager.default.enumerator(
                at: home, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { return [] }

            for case let url as URL in enumerator {
                // Don't descend into the Library — caches are handled by Smart Clean.
                if url.pathComponents.contains("Library") {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let size = values.totalFileAllocatedSize, Int64(size) >= limit
                else { continue }
                results.append(LargeFile(
                    url: url,
                    size: Int64(size),
                    modified: values.contentModificationDate ?? .distantPast))
                if results.count >= 400 { break }
            }
            return results.sorted { $0.size > $1.size }
        }.value

        files = found
    }

    /// Moves the reviewed selection to the Trash. Never hard-deletes.
    func trashSelected() -> CleanResult {
        var result = CleanResult()
        for file in files where selection.contains(file.url) {
            do {
                try SafetyGuard.trash(file.url, userReviewed: true)
                result.freedBytes += file.size
                result.removedItems += 1
            } catch {
                result.failedItems += 1
            }
        }
        files.removeAll { selection.contains($0.url) }
        selection = []
        return result
    }
}

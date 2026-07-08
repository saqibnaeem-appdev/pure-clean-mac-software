import Foundation
import Observation
import CryptoKit

/// Finds true duplicates (identical content) among images, videos, PDFs and
/// documents in a user-chosen folder. Two-stage: group by size, then verify
/// with a SHA-256 content hash so false positives are impossible.
@MainActor
@Observable
final class DuplicateFinder {

    static let mediaExtensions: Set<String> = [
        // images
        "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "bmp", "raw",
        // videos
        "mp4", "mov", "m4v", "avi", "mkv", "webm",
        // documents
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf",
    ]

    private(set) var groups: [DuplicateGroup] = []
    private(set) var isScanning = false
    private(set) var scannedFolder: URL?
    /// Files marked for removal (the kept copy is whatever remains unticked).
    var selection = Set<URL>()

    var recoverableSelected: Int64 {
        groups.reduce(0) { total, group in
            total + group.fileSize * Int64(group.files.filter(selection.contains).count)
        }
    }

    func scan(folder: URL) async {
        guard !isScanning else { return }
        isScanning = true
        scannedFolder = folder
        groups = []
        selection = []
        defer { isScanning = false }

        let found = await Task.detached(priority: .userInitiated) { () -> [DuplicateGroup] in
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
            guard let enumerator = fm.enumerator(
                at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { return [] }

            // Stage 1 — bucket by (extension-class, exact size).
            var bySize: [Int64: [URL]] = [:]
            for case let url as URL in enumerator {
                guard Self.mediaExtensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let size = values.totalFileAllocatedSize, size > 4096
                else { continue }
                bySize[Int64(size), default: []].append(url)
            }

            // Stage 2 — confirm with content hashes.
            var results: [DuplicateGroup] = []
            for (size, candidates) in bySize where candidates.count > 1 {
                var byHash: [String: [URL]] = [:]
                for url in candidates {
                    guard let hash = Self.sha256(of: url) else { continue }
                    byHash[hash, default: []].append(url)
                }
                for (hash, files) in byHash where files.count > 1 {
                    results.append(DuplicateGroup(
                        id: hash,
                        files: files.sorted { $0.path < $1.path },
                        fileSize: size))
                }
            }
            return results.sorted { $0.recoverable > $1.recoverable }
        }.value

        groups = found
    }

    nonisolated private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            guard let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    /// Trashes the ticked copies. Guards against removing *every* copy.
    func trashSelected() -> CleanResult {
        var result = CleanResult()
        for group in groups {
            var doomed = group.files.filter(selection.contains)
            // Safety: always keep at least one copy of each group.
            if doomed.count == group.files.count { doomed.removeLast() }
            for url in doomed {
                do {
                    try SafetyGuard.trash(url, userReviewed: true)
                    result.freedBytes += group.fileSize
                    result.removedItems += 1
                } catch {
                    result.failedItems += 1
                }
            }
        }
        groups = groups.compactMap { group in
            let remaining = group.files.filter { !selection.contains($0) }
            return remaining.count > 1
                ? DuplicateGroup(id: group.id, files: remaining, fileSize: group.fileSize)
                : nil
        }
        selection = []
        return result
    }
}

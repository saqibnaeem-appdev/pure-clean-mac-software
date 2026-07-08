import Foundation
import SwiftUI

extension Int64 {
    /// "8.4 GB" style human-readable size.
    var bytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Double {
    var percentFormatted: String { "\(Int((self * 100).rounded()))%" }
}

extension FileManager {

    /// Total size of a directory tree (best effort, skips unreadable items).
    func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Size of a single item — file size, or tree size for directories.
    func itemSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey])
        if values?.isDirectory == true {
            return directorySize(at: url)
        }
        return Int64(values?.totalFileAllocatedSize ?? 0)
    }
}

extension View {
    /// Standard rounded "card" chrome used across the app.
    func cardStyle() -> some View {
        self
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

import Foundation
import SwiftUI

extension Int64 {
    /// "8.4 GB" style human-readable size (decimal, like Finder).
    var bytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }

    /// "12.5 MB/s" throughput formatting.
    var rateFormatted: String {
        "\(bytesFormatted)/s"
    }
}

extension Double {
    var percentFormatted: String { "\(Int((self * 100).rounded()))%" }

    /// "42.5 °C" — one decimal, real degree sign.
    var temperatureFormatted: String { String(format: "%.1f °C", self) }
}

extension TimeInterval {
    /// "3d 4h" / "5h 12m" / "42m" uptime-style formatting.
    var uptimeFormatted: String {
        let total = Int(self)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

extension Int {
    /// Minutes → "2h 15m" (battery time remaining, scan ETA).
    var minutesFormatted: String {
        let hours = self / 60
        let minutes = self % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Seconds → "about 2 min left" / "45 s left".
    var etaFormatted: String {
        if self >= 90 { return "about \((self + 30) / 60) min left" }
        if self >= 60 { return "about a minute left" }
        return "\(Swift.max(1, self)) s left"
    }
}

extension URL {
    /// Path with the home directory abbreviated to "~".
    var abbreviatedPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

extension FileManager {

    /// Total size of a directory tree (best effort, skips unreadable items).
    /// Descends into packages too — a trashed .app must count its real size.
    func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .totalFileSizeKey, .fileSizeKey, .isRegularFileKey,
        ]
        guard let enumerator = enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize
                           ?? values.fileAllocatedSize
                           ?? values.totalFileSize
                           ?? values.fileSize ?? 0)
        }
        return total
    }

    /// Size of a single item — file size, or tree size for directories.
    func itemSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .totalFileSizeKey, .fileSizeKey,
        ])
        if values?.isDirectory == true {
            return directorySize(at: url)
        }
        return Int64(values?.totalFileAllocatedSize
                     ?? values?.fileAllocatedSize
                     ?? values?.totalFileSize
                     ?? values?.fileSize ?? 0)
    }
}

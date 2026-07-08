import Foundation
import Observation

/// Read-only storage breakdown of the folders that typically dominate a Mac.
@MainActor
@Observable
final class DiskAnalyzerManager {

    private(set) var usages: [FolderUsage] = []
    private(set) var isScanning = false

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

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

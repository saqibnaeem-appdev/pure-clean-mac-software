import Foundation
import Observation
import AppKit

/// Lists installed apps and finds their leftovers (caches, preferences,
/// logs, support files). Uninstalling trashes everything — restorable.
@MainActor
@Observable
final class AppUninstaller {

    private(set) var apps: [InstalledApp] = []
    private(set) var isScanning = false
    private(set) var isResolving = false

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]

        var found: [InstalledApp] = []
        for root in roots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for url in children where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier,
                      !bundleID.hasPrefix("com.apple.")   // never offer system apps
                else { continue }
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                found.append(InstalledApp(name: name, bundleURL: url, bundleID: bundleID))
            }
        }
        apps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Resolve sizes in the background, updating rows as they land.
        for index in apps.indices {
            let bundleURL = apps[index].bundleURL
            let size = await Task.detached(priority: .utility) {
                FileManager.default.directorySize(at: bundleURL)
            }.value
            if index < apps.count, apps[index].bundleURL == bundleURL {
                apps[index].appSize = size
            }
        }
    }

    /// Finds caches/preferences/logs/support files belonging to an app.
    func resolveRelatedFiles(for app: InstalledApp) async -> InstalledApp {
        isResolving = true
        defer { isResolving = false }

        let bundleID = app.bundleID
        let name = app.name
        let related = await Task.detached(priority: .userInitiated) { () -> [URL] in
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let library = home.appendingPathComponent("Library")
            let parents = [
                library.appendingPathComponent("Application Support"),
                library.appendingPathComponent("Caches"),
                library.appendingPathComponent("Logs"),
                library.appendingPathComponent("Containers"),
                library.appendingPathComponent("Group Containers"),
                library.appendingPathComponent("Saved Application State"),
                library.appendingPathComponent("WebKit"),
                library.appendingPathComponent("HTTPStorages"),
            ]

            var hits: [URL] = []
            for parent in parents {
                guard let children = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { continue }
                for child in children {
                    let base = child.lastPathComponent
                    if base.localizedCaseInsensitiveContains(bundleID)
                        || base == name
                        || base.hasSuffix(".\(bundleID).savedState") {
                        hits.append(child)
                    }
                }
            }
            // Preference plists.
            let prefs = library.appendingPathComponent("Preferences")
            if let plists = try? fm.contentsOfDirectory(at: prefs, includingPropertiesForKeys: nil) {
                hits.append(contentsOf: plists.filter {
                    $0.lastPathComponent.hasPrefix(bundleID)
                })
            }
            return hits
        }.value

        var resolved = app
        resolved.relatedFiles = related
        resolved.relatedSize = related.reduce(0) { $0 + FileManager.default.itemSize(at: $1) }
        return resolved
    }

    /// Trashes the app bundle and all confirmed related files.
    func uninstall(_ app: InstalledApp) -> CleanResult {
        var result = CleanResult()
        for url in [app.bundleURL] + app.relatedFiles {
            do {
                try SafetyGuard.trash(url, userReviewed: true)
                result.removedItems += 1
            } catch {
                result.failedItems += 1
            }
        }
        result.freedBytes = app.appSize + app.relatedSize
        apps.removeAll { $0.bundleURL == app.bundleURL }
        return result
    }

    func icon(for app: InstalledApp) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.bundleURL.path)
    }
}

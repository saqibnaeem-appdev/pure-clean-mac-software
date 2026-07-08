import Foundation

/// The single gatekeeper for every destructive file operation in the app.
///
/// PureClean's core promise is that it can never touch personal files.
/// `CleanerManager` only ever *proposes* paths; nothing is removed unless
/// this guard approves it. The rules are deliberately conservative — when
/// in doubt, we refuse.
enum SafetyGuard {

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Roots we are allowed to delete *inside of*. A candidate must live
    /// under one of these to even be considered.
    static let allowedRoots: [URL] = [
        home.appendingPathComponent("Library/Caches"),
        home.appendingPathComponent("Library/Logs"),
        home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
        home.appendingPathComponent("Library/Developer/Xcode/Archives"),
        home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
        home.appendingPathComponent(".Trash"),
        home.appendingPathComponent("Library/Application Support/CrashReporter"),
        FileManager.default.temporaryDirectory,
        URL(fileURLWithPath: NSTemporaryDirectory()),
    ]

    /// Extra roots that require an explicit, per-file user review
    /// (e.g. old installers in Downloads). Only these extensions qualify.
    static let reviewOnlyRoots: [URL] = [
        home.appendingPathComponent("Downloads")
    ]
    static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]

    /// Path components that must never appear in a deletable path,
    /// regardless of where it lives.
    private static let forbiddenComponents: Set<String> = [
        "Documents", "Desktop", "Pictures", "Photos", "Music", "Movies",
        "Photo Booth Library", "Photos Library.photoslibrary",
        ".git", ".ssh", ".gnupg", "node_modules",
    ]

    /// Approves a URL for deletion as part of an automatic clean.
    static func isSafeToClean(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        // Never follow into forbidden territory, even via odd nesting.
        for component in standardized.pathComponents
        where forbiddenComponents.contains(component) {
            return false
        }

        // Must live inside an allowed root.
        return allowedRoots.contains { root in
            path == root.path || path.hasPrefix(root.path + "/")
        }
    }

    /// Approves an installer file that the user explicitly reviewed.
    static func isReviewedInstaller(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard installerExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return reviewOnlyRoots.contains { path.hasPrefix($0.path + "/") }
    }

    /// Moves an item to the Trash (restorable) after a final safety check.
    /// `userReviewed` marks operations where the user explicitly selected
    /// the exact file (large files, duplicates, uninstaller) — those are
    /// still always trashed, never hard-deleted.
    @discardableResult
    static func trash(_ url: URL, userReviewed: Bool = false) throws -> Bool {
        guard userReviewed || isSafeToClean(url) || isReviewedInstaller(url) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            return true
        } catch {
            // Some cache files can't be trashed (e.g. different volume);
            // fall back to removal only for guard-approved cache paths.
            if !userReviewed, isSafeToClean(url) {
                try FileManager.default.removeItem(at: url)
                return true
            }
            throw error
        }
    }
}

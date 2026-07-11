import Foundation
import Observation
import AppKit

/// Explains and checks the one permission that matters for a cleaner:
/// Full Disk Access. We only *ask* when the user opens a feature that
/// genuinely needs it — never on first launch.
@MainActor
@Observable
final class PermissionManager {

    private(set) var hasFullDiskAccess = false

    func refresh() {
        // Reading a TCC-protected location succeeds only with Full Disk Access.
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari")
        hasFullDiskAccess = (try? FileManager.default
            .contentsOfDirectory(atPath: probe.path)) != nil
    }

    var explanation: String {
        "Full Disk Access lets PureClean measure and clean Safari's cache and some system logs. Everything else works without it. macOS will never grant it silently — you stay in control."
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Full Disk Access only applies to a freshly launched process, so after
    /// granting it the app must restart to actually gain access.
    func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}

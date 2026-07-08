import Foundation
import Observation
import AppKit
import ServiceManagement

/// Lists user LaunchAgents (the classic startup items we can manage) and
/// enables/disables them by renaming the plist — fully reversible.
/// Modern "background items" are governed by macOS itself, so we deep-link
/// users to System Settings for those.
@MainActor
@Observable
final class StartupManager {

    private(set) var items: [LoginItem] = []

    private var agentsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    func scan() {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: agentsFolder, includingPropertiesForKeys: nil) else {
            items = []
            return
        }

        items = children.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasSuffix(".plist") || name.hasSuffix(".plist.disabled") else { return nil }
            let enabled = name.hasSuffix(".plist")
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return nil }
            let label = plist["Label"] as? String ?? name
                .replacingOccurrences(of: ".plist.disabled", with: "")
                .replacingOccurrences(of: ".plist", with: "")
            let program = (plist["Program"] as? String)
                ?? (plist["ProgramArguments"] as? [String])?.first
                ?? "—"
            return LoginItem(label: label, plistURL: url, programPath: program, isEnabled: enabled)
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Toggles an agent by unloading it and renaming the plist.
    func setEnabled(_ enabled: Bool, for item: LoginItem) {
        let fm = FileManager.default
        let target: URL
        if enabled {
            target = item.plistURL.deletingPathExtension() // strips ".disabled"
        } else {
            // Stop the running agent first (best effort), then park the plist.
            ShellRunner.run("/bin/launchctl", ["bootout", "gui/\(getuid())", item.plistURL.path])
            target = item.plistURL.appendingPathExtension("disabled")
        }
        try? fm.moveItem(at: item.plistURL, to: target)
        if enabled {
            ShellRunner.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", target.path])
        }
        scan()
    }

    /// Opens System Settings → General → Login Items for the rest.
    func openSystemLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Launch PureClean at login

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}

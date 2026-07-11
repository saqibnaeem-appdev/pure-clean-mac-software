import Foundation
import Observation
import ServiceManagement

/// User preferences, backed by UserDefaults and observable from any view.
@MainActor
@Observable
final class AppSettings {

    private static let defaults = UserDefaults.standard

    /// One-time welcome + permissions flow on first launch.
    var hasCompletedOnboarding: Bool {
        didSet { Self.defaults.set(hasCompletedOnboarding, forKey: "settings.onboarded") }
    }

    /// Keep the sparkle in the menu bar (quick actions + reopen).
    var showMenuBarIcon: Bool {
        didSet { Self.defaults.set(showMenuBarIcon, forKey: "settings.menuBarIcon") }
    }

    /// Open the dashboard window when the app is launched directly.
    var showWindowAtLaunch: Bool {
        didSet { Self.defaults.set(showWindowAtLaunch, forKey: "settings.windowAtLaunch") }
    }

    /// Registered with SMAppService so macOS launches us at login.
    var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch-at-login toggle failed: \(error.localizedDescription)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    init() {
        hasCompletedOnboarding = Self.defaults.bool(forKey: "settings.onboarded")
        showMenuBarIcon = Self.defaults.object(forKey: "settings.menuBarIcon") as? Bool ?? true
        showWindowAtLaunch = Self.defaults.object(forKey: "settings.windowAtLaunch") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

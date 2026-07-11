import SwiftUI

/// Native Settings window with the standard toolbar-tab layout.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            ScanningSettings()
                .tabItem { Label("Scanning", systemImage: "sparkles") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Launch PureClean at login", isOn: $settings.launchAtLogin)
                Toggle("Open the dashboard window at launch", isOn: $settings.showWindowAtLaunch)
            } footer: {
                Text("With both off, PureClean starts silently in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show icon in the menu bar", isOn: $settings.showMenuBarIcon)
            } footer: {
                Text(settings.showMenuBarIcon
                     ? "Closing the dashboard keeps PureClean running in the menu bar for quick actions and background cleaning."
                     : "Without the menu bar icon, reopen PureClean from Launchpad or the Applications folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                LabeledContent("Theme", value: "Follows the system Light / Dark setting")
            }

            Section {
                Button("Quit PureClean") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Form {
            Section {
                Toggle("Storage running low (under 10%)",
                       isOn: Bindable(app.notifications).storageAlerts)
                Toggle("Memory pressure high (over 90%)",
                       isOn: Bindable(app.notifications).memoryAlerts)
                Toggle("Caches exceed 5 GB",
                       isOn: Bindable(app.notifications).cacheAlerts)
            } footer: {
                Text("At most one alert per topic every 6 hours — PureClean never nags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scanning

private struct ScanningSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Form {
            Section {
                Picker("Automatic clean", selection: Bindable(app.scheduler).schedule) {
                    ForEach(CleanSchedule.allCases) { schedule in
                        Text(schedule.label).tag(schedule)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(scheduleFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy & Safety") {
                LabeledContent("Personal files",
                               value: "Never scanned or removed")
                LabeledContent("Removals",
                               value: "Go to the Trash whenever possible")
                LabeledContent("Language file stripping",
                               value: "Not offered — it breaks app signatures")
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: app.permissions.hasFullDiskAccess
                          ? "checkmark.shield.fill" : "shield.slash")
                        .foregroundStyle(app.permissions.hasFullDiskAccess ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Disk Access — \(app.permissions.hasFullDiskAccess ? "granted" : "not granted")")
                            .font(.system(size: 12, weight: .medium))
                        Text(app.permissions.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !app.permissions.hasFullDiskAccess {
                    Button("Open Privacy Settings…") {
                        app.permissions.openFullDiskAccessSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { app.permissions.refresh() }
    }

    private var scheduleFootnote: String {
        if app.scheduler.schedule == .off {
            return "Automatic cleaning is off. Scheduled cleans only touch the always-safe categories (caches, logs, temporary files)."
        }
        if let last = app.scheduler.lastCleanDate {
            return "Last clean: \(last.formatted(date: .abbreviated, time: .shortened)). Only always-safe categories are cleaned automatically."
        }
        return "The first clean will run shortly. Only always-safe categories are cleaned automatically."
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Theme.brandGradient,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: .blue.opacity(0.35), radius: 10, y: 5)
                .padding(.top, 24)

            Text("PureClean")
                .font(.system(size: 18, weight: .bold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Safe cleaning only — your documents, photos and projects are never touched. Every removal is restorable from the Trash.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Text("Created by AWS NextGen IT")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.brandGradientHorizontal)
                .padding(.top, 4)

            Text("© 2026 AWS NextGen IT LTD")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var launchAtLogin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                scheduleCard
                notificationsCard
                permissionsCard
                generalCard
                aboutCard
            }
            .padding(14)
        }
        .onAppear {
            launchAtLogin = app.startup.launchAtLogin
            app.permissions.refresh()
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Scheduled Cleaning")
            Picker("Run Smart Clean", selection: Bindable(app.scheduler).schedule) {
                ForEach(CleanSchedule.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            Text(scheduleFootnote)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var scheduleFootnote: String {
        if app.scheduler.schedule == .off {
            return "Automatic cleaning is off. Scheduled cleans only touch the always-safe categories (caches, logs, temp)."
        }
        if let last = app.scheduler.lastCleanDate {
            return "Last clean: \(last.formatted(date: .abbreviated, time: .shortened)). Only always-safe categories are cleaned automatically."
        }
        return "First clean will run shortly. Only always-safe categories are cleaned automatically."
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Notifications")
            Toggle("Storage running low (under 10%)", isOn: Bindable(app.notifications).storageAlerts)
            Toggle("Memory pressure high (over 90%)", isOn: Bindable(app.notifications).memoryAlerts)
            Toggle("Caches exceed 5 GB", isOn: Bindable(app.notifications).cacheAlerts)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 11.5))
        .cardStyle()
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Permissions")
            HStack(spacing: 8) {
                Image(systemName: app.permissions.hasFullDiskAccess
                      ? "checkmark.shield.fill" : "shield.slash")
                    .foregroundStyle(app.permissions.hasFullDiskAccess ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access — \(app.permissions.hasFullDiskAccess ? "granted" : "not granted")")
                        .font(.system(size: 11.5, weight: .medium))
                    Text(app.permissions.explanation)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !app.permissions.hasFullDiskAccess {
                Button("Open Privacy Settings…") {
                    app.permissions.openFullDiskAccessSettings()
                }
                .controlSize(.small)
            }
        }
        .cardStyle()
    }

    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "General")
            Toggle("Launch PureClean at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11.5))
                .onChange(of: launchAtLogin) { _, newValue in
                    app.startup.setLaunchAtLogin(newValue)
                }
            Button("Quit PureClean") {
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.small)
        }
        .cardStyle()
    }

    private var aboutCard: some View {
        VStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
            Text("PureClean 1.0")
                .font(.system(size: 12, weight: .semibold))
            Text("Safe cleaning only — your documents, photos and projects are never touched. Every removal is restorable from the Trash.")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Created by AWS NextGen IT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple],
                                   startPoint: .leading, endPoint: .trailing))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

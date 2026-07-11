import SwiftUI
import UserNotifications

/// First-launch flow: a welcome page, then one permissions page that asks
/// for everything up front — Full Disk Access (live status, flips green the
/// moment it's granted in System Settings), notifications, and launch at
/// login. Standard commercial-app onboarding; skippable, revisitable in
/// Settings.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var step = 0
    @State private var openedSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if step == 0 {
                    welcome
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .offset(x: -40))))
                } else {
                    permissions
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 40)),
                            removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)

            footer
        }
        .frame(width: 560, height: 620)
        .background {
            ZStack {
                VisualEffectView(material: .underWindowBackground)
                AuroraBackground()
            }
            .ignoresSafeArea()
        }
        .task {
            // Returning users only come back here for missing permissions —
            // jump straight to the setup step.
            if app.settings.hasCompletedOnboarding { step = 1 }
            app.notifications.refreshAuthStatus()
            // Live-poll Full Disk Access so granting it in System Settings
            // updates the card without the user doing anything.
            while !Task.isCancelled {
                app.permissions.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: - Step 1 · Welcome

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.purple.opacity(0.35), .clear],
                                         center: .center, startRadius: 8, endRadius: 110))
                    .frame(width: 220, height: 220)
                    .blur(radius: 12)
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 104, height: 104)
                    .background(Theme.brandGradient,
                                in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .purple.opacity(0.5), radius: 18, y: 8)
            }

            VStack(spacing: 6) {
                Text("Welcome to PureClean")
                    .font(Theme.display(28, .bold))
                Text("Start with a quick, safe scan of your Mac.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "sparkles", tint: .purple, title: "Smart Scan",
                           detail: "Caches, logs, leftovers and junk — found and cleaned safely.")
                featureRow(icon: "waveform.path.ecg", tint: .cyan, title: "Live Performance",
                           detail: "CPU, memory, disk, network, GPU, battery and sensors in real time.")
                featureRow(icon: "checkmark.shield.fill", tint: .green, title: "Safe by design",
                           detail: "Personal files are never touched. Removals are restorable from the Trash.")
            }
            .padding(.horizontal, 60)
            Spacer()
        }
    }

    private func featureRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: icon, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Step 2 · Permissions

    private var permissions: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            VStack(spacing: 6) {
                Text("Set up PureClean")
                    .font(Theme.display(24, .bold))
                Text("Grant these once so every feature works from the start.\nEverything is optional and can be changed later in Settings.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    permissionCard(
                        icon: "lock.shield.fill",
                        tint: app.permissions.hasFullDiskAccess ? .green : .orange,
                        title: "Full Disk Access",
                        detail: "Needed to measure and empty the Trash and clean Safari & Mail caches. Enable PureClean in the list, then restart the app — macOS only applies it to a fresh launch.",
                        granted: app.permissions.hasFullDiskAccess,
                        actionTitle: "Open System Settings…"
                    ) {
                        openedSettings = true
                        app.permissions.openFullDiskAccessSettings()
                    }
                    if openedSettings && !app.permissions.hasFullDiskAccess {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text("Already enabled it? Restart to apply.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Restart PureClean") {
                                app.permissions.relaunchApp()
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: openedSettings)

                permissionCard(
                    icon: "bell.badge.fill",
                    tint: notificationsGranted ? .green : .blue,
                    title: "Notifications",
                    detail: "A quiet heads-up when storage runs low or memory pressure spikes — at most one alert per topic every 6 hours.",
                    granted: notificationsGranted,
                    actionTitle: "Enable Alerts"
                ) {
                    app.notifications.requestPermissionIfNeeded()
                }

                launchAtLoginCard
            }
            .padding(.horizontal, 44)
            Spacer(minLength: 12)
        }
    }

    private var notificationsGranted: Bool {
        app.notifications.authStatus == .authorized
            || app.notifications.authStatus == .provisional
    }

    private func permissionCard(icon: String, tint: Color, title: String,
                                detail: String, granted: Bool,
                                actionTitle: String,
                                action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 13) {
            IconBadge(systemName: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(actionTitle, action: action)
                    .controlSize(.regular)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: granted)
        .glassCard(padding: 14)
    }

    private var launchAtLoginCard: some View {
        HStack(alignment: .center, spacing: 13) {
            IconBadge(systemName: "power", tint: .indigo, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at Login").font(.system(size: 13, weight: .semibold))
                Text("Keep PureClean in your menu bar so monitoring and scheduled cleaning are always on.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Bindable(app.settings).launchAtLogin)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .glassCard(padding: 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step == 0 {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    step = 0
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? AnyShapeStyle(Theme.brandGradientHorizontal)
                                            : AnyShapeStyle(.quaternary))
                        .frame(width: index == step ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)

            Spacer()
            PrimaryGradientButton(
                title: step == 0 ? "Continue" : "Get Started",
                icon: step == 0 ? "arrow.right" : "sparkles",
                fullWidth: false
            ) {
                if step == 0 { step = 1 } else { finish() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
    }

    private func finish() {
        app.settings.hasCompletedOnboarding = true
        // Pick up anything the user just granted.
        app.permissions.refresh()
        app.trash.refresh()
    }
}

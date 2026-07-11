import SwiftUI
import AppKit

/// The dashboard window: custom sidebar + the selected page, drawn over a
/// full-window blur with a soft aurora glow.
struct MainWindowView: View {
    @Environment(AppState.self) private var app
    /// The setup sheet re-appears every launch until Full Disk Access is
    /// granted — but never twice in one session.
    @State private var setupDismissedThisSession = false

    /// Guards the one-time "start hidden in the menu bar" launch behaviour.
    private static var didHandleLaunch = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Divider().opacity(0.4)
            detail
        }
        .background {
            ZStack {
                VisualEffectView(material: .underWindowBackground)
                AuroraBackground()
            }
            .ignoresSafeArea()
        }
        .background(WindowAccessor { window in configure(window) })
        .sheet(isPresented: onboardingBinding) {
            OnboardingView()
                .environment(app)
        }
    }

    /// Presents the welcome flow on first launch, and re-presents the
    /// permissions step at launch while Full Disk Access is still missing —
    /// the standard "set up once at the start" behaviour.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: {
                guard !setupDismissedThisSession else { return false }
                return !app.settings.hasCompletedOnboarding
                    || !app.permissions.hasFullDiskAccess
            },
            set: { showing in
                if !showing {
                    setupDismissedThisSession = true
                    app.settings.hasCompletedOnboarding = true
                }
            })
    }

    private var detail: some View {
        ZStack {
            pageView
                .id(app.route)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 10)),
                    removal: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.route)
    }

    @ViewBuilder
    private var pageView: some View {
        switch app.route {
        case .dashboard: DashboardView()
        case .smartScan: SmartScanView()
        case .performance: PerformanceView()
        case .storage: StorageView()
        case .trash: TrashView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .uninstaller: UninstallerView()
        case .startup: StartupView()
        }
    }

    private func configure(_ window: NSWindow) {
        guard app.mainWindow !== window else { return }
        app.mainWindow = window
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed

        // Regular app (Dock icon) while the dashboard is open; retreat to the
        // menu bar when it closes instead of quitting.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in NSApp.setActivationPolicy(.accessory) }
        }

        if !Self.didHandleLaunch {
            Self.didHandleLaunch = true
            if !app.settings.showWindowAtLaunch {
                window.close()
            }
        }
    }
}

// MARK: - Sidebar

private struct SidebarSection: Identifiable {
    let id: String
    let routes: [Route]
}

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Namespace private var pillNamespace

    private let sections: [SidebarSection] = [
        SidebarSection(id: "Overview", routes: [.dashboard, .smartScan, .performance]),
        SidebarSection(id: "Storage", routes: [.storage, .trash, .largeFiles, .duplicates]),
        SidebarSection(id: "Applications", routes: [.uninstaller, .startup]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 46)
                .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(section.id)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .kerning(0.5)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 3)
                            ForEach(section.routes) { route in
                                SidebarRow(route: route, namespace: pillNamespace)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 22)
            }

            Spacer(minLength: 0)
            footer
                .padding(12)
        }
        .frame(width: 232)
        .background(VisualEffectView(material: .sidebar).ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.brandGradient,
                            in: RoundedRectangle(cornerRadius: 9.5, style: .continuous))
                .shadow(color: .purple.opacity(0.45), radius: 7, y: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text("PureClean")
                    .font(Theme.display(15.5, .bold))
                Text("System care")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                    Text("Settings")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct SidebarRow: View {
    @Environment(AppState.self) private var app
    let route: Route
    let namespace: Namespace.ID
    @State private var hovering = false

    private var selected: Bool { app.route == route }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                app.route = route
            }
        } label: {
            HStack(spacing: 10) {
                // Colored icon chip (Settings-app style) — always tinted so
                // the sidebar reads at a glance.
                Image(systemName: route.icon)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .background(
                        route.tint.gradient,
                        in: RoundedRectangle(cornerRadius: 7.5, style: .continuous))
                    .shadow(color: route.tint.opacity(selected || hovering ? 0.5 : 0.22),
                            radius: selected ? 5 : 3, y: 2)
                    .scaleEffect(hovering && !selected ? 1.08 : 1)
                Text(route.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(Color.primary.opacity(selected ? 1 : 0.8))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background {
                if selected {
                    pill
                        .matchedGeometryEffect(id: "sidebar-pill", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.quaternary.opacity(0.45))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Frosted selection pill with a brand-tinted glow.
    @ViewBuilder
    private var pill: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(route.tint.opacity(0.35)), in: shape)
                .shadow(color: route.tint.opacity(0.25), radius: 7, y: 3)
        } else {
            shape
                .fill(.quaternary.opacity(0.7))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom)))
                .shadow(color: route.tint.opacity(0.25), radius: 7, y: 3)
        }
    }
}

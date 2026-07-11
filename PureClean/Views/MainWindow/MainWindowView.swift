import SwiftUI
import AppKit

/// The dashboard window: custom sidebar + the selected page, drawn over a
/// full-window blur with a soft aurora glow.
struct MainWindowView: View {
    @Environment(AppState.self) private var app

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
        .frame(width: 218)
        .background(VisualEffectView(material: .sidebar).ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.brandGradient,
                            in: RoundedRectangle(cornerRadius: 8.5, style: .continuous))
                .shadow(color: .blue.opacity(0.35), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text("PureClean")
                    .font(.system(size: 14.5, weight: .bold))
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
            HStack(spacing: 9) {
                Image(systemName: route.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(route.tint))
                    .frame(width: 20)
                Text(route.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.brandGradient)
                        .shadow(color: .blue.opacity(0.3), radius: 5, y: 2)
                        .matchedGeometryEffect(id: "sidebar-pill", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.quaternary.opacity(0.55))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

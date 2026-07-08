import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard, clean, tools, monitor, settings
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: "gauge.medium"
        case .clean: "sparkles"
        case .tools: "wrench.and.screwdriver"
        case .monitor: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
    var label: String {
        switch self {
        case .dashboard: "Home"
        case .clean: "Clean"
        case .tools: "Tools"
        case .monitor: "Monitor"
        case .settings: "Settings"
        }
    }
}

/// The menu bar popover: an animated aurora background, a native-style top
/// segmented switcher and the current tab's content.
struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var tab: AppTab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            switcher
            Divider().opacity(0.5)
            Group {
                switch tab {
                case .dashboard: DashboardView()
                case .clean: CleanView()
                case .tools: ToolsView()
                case .monitor: MonitorView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .id(tab)
        }
        .frame(width: 400, height: 600)
        .background(AuroraBackground())
    }

    /// macOS-native segmented switcher (replaces the iOS-style bottom bar).
    private var switcher: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { item in
                let selected = tab == item
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { tab = item }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                        if selected {
                            Text(item.label)
                                .font(.system(size: 11.5, weight: .semibold))
                                .fixedSize()
                        }
                    }
                    .foregroundStyle(selected ? .white : .secondary)
                    .padding(.horizontal, selected ? 12 : 9)
                    .padding(.vertical, 6)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [.blue, .purple],
                                                     startPoint: .leading, endPoint: .trailing))
                                .matchedGeometryEffect(id: "pill", in: switcherNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .padding(10)
    }

    @Namespace private var switcherNamespace
}

/// Slowly drifting gradient blobs behind the whole popover — the app's
/// signature "3D-ish" depth without any heavy rendering.
struct AuroraBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Circle()
                .fill(RadialGradient(colors: [.blue.opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: 160))
                .frame(width: 320, height: 320)
                .offset(x: animate ? -90 : -60, y: animate ? -170 : -210)
                .blur(radius: 40)
            Circle()
                .fill(RadialGradient(colors: [.purple.opacity(0.32), .clear],
                                     center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 300, height: 300)
                .offset(x: animate ? 110 : 80, y: animate ? 60 : 110)
                .blur(radius: 44)
            Circle()
                .fill(RadialGradient(colors: [.pink.opacity(0.22), .clear],
                                     center: .center, startRadius: 0, endRadius: 130))
                .frame(width: 260, height: 260)
                .offset(x: animate ? -70 : -40, y: animate ? 200 : 170)
                .blur(radius: 46)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

#Preview {
    RootView().environment(AppState())
}

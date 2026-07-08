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

/// The menu bar popover: content area + a compact bottom tab bar.
struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var tab: AppTab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()
            tabBar
        }
        .frame(width: 400, height: 600)
        .background(.regularMaterial)
    }

    private var tabBar: some View {
        HStack {
            ForEach(AppTab.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.18)) { tab = item }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: .medium))
                        Text(item.label)
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .background(.bar)
    }
}

#Preview {
    RootView().environment(AppState())
}

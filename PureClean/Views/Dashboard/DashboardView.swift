import SwiftUI

/// Landing page: system health at a glance + the Smart Scan hero action.
struct DashboardView: View {
    @Environment(AppState.self) private var app

    private var snap: SystemSnapshot { app.monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.gridSpacing) {
                PageHeader("Dashboard", subtitle: greetingSubtitle) {
                    HStack(spacing: 8) {
                        if snap.smartStatus == "Verified" {
                            Badge(text: "Disk Healthy", color: .green)
                        }
                        Badge(text: "Memory \(snap.memory.pressure.label)",
                              color: snap.memory.pressure.color)
                    }
                }

                heroCard

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacing),
                                         count: 3),
                          spacing: Theme.gridSpacing) {
                    ringCard(
                        title: "Storage", icon: "internaldrive.fill", tint: .blue,
                        fraction: snap.disk.usedFraction,
                        value: snap.disk.available.bytesFormatted,
                        label: "available",
                        footer: snap.disk.purgeable > 0
                            ? "\(snap.disk.purgeable.bytesFormatted) purgeable"
                            : "of \(snap.disk.total.bytesFormatted)",
                        route: .storage)
                    ringCard(
                        title: "Memory", icon: "memorychip.fill", tint: .purple,
                        fraction: snap.memory.usedFraction,
                        value: snap.memory.used.bytesFormatted,
                        label: "in use",
                        footer: "of \(snap.memory.total.bytesFormatted)",
                        route: .performance)
                    ringCard(
                        title: "CPU", icon: "cpu.fill", tint: .cyan,
                        fraction: snap.cpu.usage,
                        value: snap.cpu.usage.percentFormatted,
                        label: "load",
                        footer: String(format: "load avg %.2f", snap.cpu.loadAverage),
                        route: .performance)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacing),
                                         count: 3),
                          spacing: Theme.gridSpacing) {
                    navTile(route: .trash, icon: "trash.fill", tint: .red, title: "Trash",
                            value: app.trash.needsFullDiskAccess
                                ? "—" : app.trash.totalSize.bytesFormatted,
                            detail: app.trash.needsFullDiskAccess
                                ? "needs Full Disk Access"
                                : "\(app.trash.itemCount) item\(app.trash.itemCount == 1 ? "" : "s")")
                    if snap.battery.hasBattery {
                        navTile(route: .performance,
                                icon: snap.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                                tint: .green, title: "Battery",
                                value: "\(snap.battery.percentage)%",
                                detail: snap.battery.healthPercent > 0
                                    ? "\(snap.battery.healthPercent)% health · \(snap.battery.cycleCount) cycles"
                                    : snap.battery.powerSource)
                    } else {
                        navTile(route: .performance, icon: "powerplug.fill", tint: .green,
                                title: "Power", value: "Desktop Mac", detail: "no battery")
                    }
                    navTile(route: .performance, icon: "network", tint: .orange, title: "Network",
                            value: "↓ \(snap.network.inPerSec.rateFormatted)",
                            detail: "↑ \(snap.network.outPerSec.rateFormatted)")
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    private var greetingSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Working late"
        }
        return "\(greeting) — your Mac is running \(snap.uptime.uptimeFormatted) since restart."
    }

    // MARK: - Hero

    private var heroCard: some View {
        HStack(spacing: 18) {
            PulsingSparkle()
            VStack(alignment: .leading, spacing: 3) {
                Text("Smart Scan")
                    .font(.system(size: 16, weight: .bold))
                Text(heroSubtitle)
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PrimaryGradientButton(
                title: app.scanner.hasResults ? "View Results" : "Scan Now",
                icon: "sparkles",
                isBusy: app.scanner.isScanning,
                fullWidth: false
            ) {
                if app.scanner.hasResults || app.scanner.isScanning {
                    withAnimation { app.route = .smartScan }
                } else {
                    app.runSmartScan()
                }
            }
        }
        .glassCard()
        .hoverLift()
    }

    private var heroSubtitle: String {
        if app.scanner.isScanning {
            return "Scanning… \(app.scanner.progress.filesScanned) files inspected so far."
        }
        if app.scanner.hasResults, app.scanner.recoverableTotal > 0 {
            return "You can safely recover \(app.scanner.recoverableTotal.bytesFormatted)."
        }
        return "Find caches, logs, leftovers and junk — nothing personal is ever touched."
    }

    // MARK: - Cards

    private func ringCard(title: String, icon: String, tint: Color,
                          fraction: Double, value: String, label: String,
                          footer: String, route: Route) -> some View {
        Button {
            withAnimation { app.route = route }
        } label: {
            VStack(spacing: 12) {
                HStack(spacing: 7) {
                    IconBadge(systemName: icon, tint: tint, size: 24)
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                MetricRing(fraction: fraction, tint: tint, size: 104) {
                    VStack(spacing: 0) {
                        Text(value)
                            .font(Theme.display(15, .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .animatedNumber(value)
                        Text(label)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                }
                Text(footer)
                    .font(Theme.footnote())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .glassCard(padding: 16)
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .hoverLift()
    }

    private func navTile(route: Route, icon: String, tint: Color,
                         title: String, value: String, detail: String) -> some View {
        Button {
            withAnimation { app.route = route }
        } label: {
            StatTile(icon: icon, tint: tint, title: title, value: value, detail: detail)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// The dashboard hero's softly pulsing brand mark.
private struct PulsingSparkle: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.brandGradient)
                .frame(width: 54, height: 54)
                .shadow(color: .purple.opacity(0.45), radius: pulse ? 16 : 8, y: 4)
            Circle()
                .stroke(.blue.opacity(0.35), lineWidth: 1.5)
                .frame(width: 54, height: 54)
                .scaleEffect(pulse ? 1.35 : 1)
                .opacity(pulse ? 0 : 0.8)
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

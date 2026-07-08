import SwiftUI
import Charts

/// Live performance monitor — refreshed every second by SystemStatsManager.
struct MonitorView: View {
    @Environment(AppState.self) private var app

    private var snap: SystemSnapshot { app.stats.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                liveChart(title: "CPU", values: app.stats.cpuHistory,
                          current: snap.cpuUsage.percentFormatted, tint: .cyan)
                liveChart(title: "Memory", values: app.stats.memHistory,
                          current: "\(snap.memory.used.bytesFormatted) / \(snap.memory.total.bytesFormatted)",
                          tint: .purple)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    StatCard(icon: "arrow.down.circle", title: "Network In",
                             value: "\(snap.networkInPerSec.bytesFormatted)/s", tint: .green)
                    StatCard(icon: "arrow.up.circle", title: "Network Out",
                             value: "\(snap.networkOutPerSec.bytesFormatted)/s", tint: .orange)
                    StatCard(icon: "internaldrive", title: "Disk Free",
                             value: snap.diskFree.bytesFormatted,
                             detail: "of \(snap.diskTotal.bytesFormatted)", tint: .blue)
                    StatCard(icon: "heart.text.square", title: "Disk Health",
                             value: snap.smartStatus,
                             detail: "SMART status", tint: .pink)
                    StatCard(icon: "memorychip", title: "App Memory",
                             value: snap.memory.active.bytesFormatted,
                             detail: "active", tint: .purple)
                    StatCard(icon: "thermometer.medium", title: "Temperature",
                             value: "N/A",
                             detail: "not exposed by macOS", tint: .red)
                }
            }
            .padding(14)
        }
    }

    private func liveChart(title: String, values: [Double], current: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(current)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(tint.opacity(0.18))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(tint)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v.percentFormatted).font(.system(size: 8))
                        }
                    }
                }
            }
            .frame(height: 84)
        }
        .cardStyle()
    }
}

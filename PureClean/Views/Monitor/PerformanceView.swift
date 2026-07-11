import SwiftUI

/// Live performance dashboard — every value refreshed by SystemMonitor.
struct PerformanceView: View {
    @Environment(AppState.self) private var app

    private var snap: SystemSnapshot { app.monitor.snapshot }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacing, alignment: .top),
              count: 2)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.gridSpacing) {
                PageHeader("Performance",
                           subtitle: "\(snap.cpu.brand) · up \(snap.uptime.uptimeFormatted)") {
                    Badge(text: "Live", color: .green)
                }

                LazyVGrid(columns: columns, spacing: Theme.gridSpacing) {
                    cpuCard
                    memoryCard
                    networkCard
                    diskCard
                    gpuCard
                    if snap.battery.hasBattery {
                        batteryCard
                    } else {
                        systemCard
                    }
                    sensorsCard
                    if snap.battery.hasBattery {
                        systemCard
                    }
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    // MARK: - Card scaffold

    private func card(icon: String, tint: Color, title: String,
                      value: String, valueTint: Color = .primary,
                      @ViewBuilder content: @escaping () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    IconBadge(systemName: icon, tint: tint, size: 26)
                    Text(title)
                        .font(Theme.cardTitle())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(valueTint)
                    .animatedNumber(value)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
        .hoverLift()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.caption())
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .animatedNumber(value)
        }
    }

    // MARK: - CPU

    private var cpuCard: some View {
        card(icon: "cpu.fill", tint: .cyan, title: "CPU",
             value: snap.cpu.usage.percentFormatted) {
            VStack(alignment: .leading, spacing: 10) {
                HistoryChart(values: app.monitor.cpuHistory, tint: .cyan)
                CoreActivityBars(values: snap.cpu.perCore)
                HStack {
                    infoRow("User", snap.cpu.userUsage.percentFormatted)
                        .frame(maxWidth: .infinity)
                    infoRow("System", snap.cpu.systemUsage.percentFormatted)
                        .frame(maxWidth: .infinity)
                    infoRow("Load", String(format: "%.2f", snap.cpu.loadAverage))
                        .frame(maxWidth: .infinity)
                }
                infoRow("Cores", coreDescription)
                if snap.cpu.frequencyMHz > 0 {
                    infoRow("Frequency", String(format: "%.2f GHz", Double(snap.cpu.frequencyMHz) / 1000))
                }
            }
        }
    }

    private var coreDescription: String {
        if snap.cpu.efficiencyCores > 0 {
            return "\(snap.cpu.performanceCores) performance + \(snap.cpu.efficiencyCores) efficiency"
        }
        return "\(max(snap.cpu.performanceCores, snap.cpu.perCore.count)) cores"
    }

    // MARK: - Memory

    private var memoryCard: some View {
        let memory = snap.memory
        return card(icon: "memorychip.fill", tint: .purple, title: "Memory",
                    value: memory.used.bytesFormatted) {
            VStack(alignment: .leading, spacing: 10) {
                HistoryChart(values: app.monitor.memHistory, tint: .purple)
                SegmentBar(segments: [
                    .init(id: "app", fraction: fraction(memory.appMemory, of: memory.total), color: .purple),
                    .init(id: "wired", fraction: fraction(memory.wired, of: memory.total), color: .indigo),
                    .init(id: "compressed", fraction: fraction(memory.compressed, of: memory.total), color: .pink),
                    .init(id: "cached", fraction: fraction(memory.cached, of: memory.total), color: .teal),
                ], height: 10)
                HStack(spacing: 10) {
                    legend("App", .purple, memory.appMemory)
                    legend("Wired", .indigo, memory.wired)
                    legend("Compressed", .pink, memory.compressed)
                    legend("Cached", .teal, memory.cached)
                }
                HStack {
                    infoRow("Free", memory.free.bytesFormatted)
                        .frame(maxWidth: .infinity)
                    infoRow("Swap", memory.swapTotal > 0
                            ? "\(memory.swapUsed.bytesFormatted) of \(memory.swapTotal.bytesFormatted)"
                            : "none")
                        .frame(maxWidth: .infinity)
                }
                HStack {
                    Text("Pressure")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Badge(text: memory.pressure.label, color: memory.pressure.color)
                }
            }
        }
    }

    private func legend(_ label: String, _ color: Color, _ bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(bytes.bytesFormatted)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fraction(_ part: Int64, of total: Int64) -> Double {
        total > 0 ? Double(part) / Double(total) : 0
    }

    // MARK: - Network

    private var networkCard: some View {
        let network = snap.network
        return card(icon: "network", tint: .orange, title: "Network",
                    value: "↓ \(network.inPerSec.rateFormatted)") {
            VStack(alignment: .leading, spacing: 10) {
                DualHistoryChart(series: [
                    .init(id: "down", values: app.monitor.netInHistory, tint: .orange),
                    .init(id: "up", values: app.monitor.netOutHistory, tint: .blue),
                ])
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(.orange).frame(width: 7, height: 7)
                        Text("Down \(network.inPerSec.rateFormatted)")
                            .font(.system(size: 10, weight: .medium))
                            .animatedNumber(network.inPerSec)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(.blue).frame(width: 7, height: 7)
                        Text("Up \(network.outPerSec.rateFormatted)")
                            .font(.system(size: 10, weight: .medium))
                            .animatedNumber(network.outPerSec)
                    }
                    Spacer()
                }
                infoRow("Interface", network.interfaceName)
                infoRow("IP Address", network.ipAddress)
                if let ssid = network.wifiSSID {
                    infoRow("Wi-Fi", ssid)
                }
                if let rssi = network.wifiRSSI {
                    infoRow("Signal", "\(rssi) dBm")
                }
                if let rate = network.wifiTxRateMbps {
                    infoRow("Link Rate", "\(Int(rate)) Mbps")
                }
            }
        }
    }

    // MARK: - Disk

    private var diskCard: some View {
        let disk = snap.disk
        return card(icon: "internaldrive.fill", tint: .blue, title: "Disk",
                    value: disk.available.bytesFormatted + " free") {
            VStack(alignment: .leading, spacing: 10) {
                DualHistoryChart(series: [
                    .init(id: "read", values: app.monitor.diskReadHistory, tint: .blue),
                    .init(id: "write", values: app.monitor.diskWriteHistory, tint: .pink),
                ])
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(.blue).frame(width: 7, height: 7)
                        Text("Read \(snap.diskIO.readPerSec.rateFormatted)")
                            .font(.system(size: 10, weight: .medium))
                            .animatedNumber(snap.diskIO.readPerSec)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(.pink).frame(width: 7, height: 7)
                        Text("Write \(snap.diskIO.writePerSec.rateFormatted)")
                            .font(.system(size: 10, weight: .medium))
                            .animatedNumber(snap.diskIO.writePerSec)
                    }
                    Spacer()
                }
                SegmentBar(segments: [
                    .init(id: "used", fraction: disk.usedFraction, color: .blue),
                    .init(id: "purgeable",
                          fraction: fraction(disk.purgeable, of: disk.total), color: .orange),
                ], height: 10)
                infoRow("Used", disk.used.bytesFormatted)
                infoRow("Purgeable", disk.purgeable.bytesFormatted)
                infoRow("SMART Status", snap.smartStatus)
            }
        }
    }

    // MARK: - GPU

    private var gpuCard: some View {
        let gpu = snap.gpu
        return card(icon: "cube.transparent.fill", tint: .pink, title: "GPU",
                    value: gpu.utilization.map(\.percentFormatted) ?? "—") {
            VStack(alignment: .leading, spacing: 10) {
                if let utilization = gpu.utilization {
                    LevelBar(fraction: utilization, tint: .pink, height: 10)
                }
                infoRow("Chip", gpu.name)
                if let memory = gpu.memoryUsed {
                    infoRow("Memory In Use", memory.bytesFormatted)
                }
                if let temp = snap.sensors.gpuTemperature {
                    infoRow("Temperature", temp.temperatureFormatted)
                }
                if gpu.utilization == nil {
                    Text("This Mac's graphics driver doesn't publish a utilization counter.")
                        .font(Theme.footnote())
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Battery

    private var batteryCard: some View {
        let battery = snap.battery
        return card(icon: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                    tint: .green, title: "Battery",
                    value: "\(battery.percentage)%") {
            VStack(alignment: .leading, spacing: 10) {
                LevelBar(fraction: Double(battery.percentage) / 100,
                         tint: battery.percentage < 20 ? .red : .green, height: 10)
                infoRow("Status", batteryStatus(battery))
                if battery.healthPercent > 0 {
                    infoRow("Health", "\(battery.healthPercent)%")
                }
                infoRow("Cycle Count", "\(battery.cycleCount)")
                if battery.maxCapacitymAh > 0 {
                    infoRow("Capacity", "\(battery.currentCapacitymAh) / \(battery.maxCapacitymAh) mAh")
                }
                if battery.designCapacitymAh > 0 {
                    infoRow("Design Capacity", "\(battery.designCapacitymAh) mAh")
                }
                if let temp = battery.temperature {
                    infoRow("Temperature", temp.temperatureFormatted)
                }
            }
        }
    }

    private func batteryStatus(_ battery: BatteryStats) -> String {
        if battery.isCharging {
            if let minutes = battery.timeToFullMinutes {
                return "Charging · \(minutes.minutesFormatted) to full"
            }
            return "Charging"
        }
        if battery.isPluggedIn { return "On power adapter" }
        if let minutes = battery.timeToEmptyMinutes {
            return "On battery · \(minutes.minutesFormatted) left"
        }
        return "On battery"
    }

    // MARK: - Sensors

    private var sensorsCard: some View {
        let sensors = snap.sensors
        return card(icon: "fanblades.fill", tint: .teal, title: "Sensors",
                    value: sensors.cpuTemperature.map(\.temperatureFormatted) ?? "—") {
            VStack(alignment: .leading, spacing: 10) {
                if let cpu = sensors.cpuTemperature {
                    infoRow("CPU Temperature", cpu.temperatureFormatted)
                }
                if let gpu = sensors.gpuTemperature {
                    infoRow("GPU Temperature", gpu.temperatureFormatted)
                }
                if sensors.fans.isEmpty {
                    if sensors.fanCount == 0 {
                        Text(sensors.cpuTemperature == nil
                             ? "This Mac doesn't expose fan or temperature sensors to apps."
                             : "This Mac is fanless — cooled passively.")
                            .font(Theme.footnote())
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(sensors.fans) { fan in
                        infoRow("Fan \(fan.id + 1)", "\(fan.rpm) RPM")
                    }
                }
            }
        }
    }

    // MARK: - System

    private var systemCard: some View {
        card(icon: "desktopcomputer", tint: .indigo, title: "System",
             value: snap.uptime.uptimeFormatted) {
            VStack(alignment: .leading, spacing: 10) {
                infoRow("Chip", snap.cpu.brand)
                infoRow("Cores", coreDescription)
                infoRow("macOS", snap.osVersion
                    .replacingOccurrences(of: "Version ", with: ""))
                infoRow("Memory", snap.memory.total.bytesFormatted)
                infoRow("Volume", "\(snap.disk.volumeName) (\(snap.disk.fileSystem))")
                infoRow("Power Source", snap.battery.hasBattery ? snap.battery.powerSource : "AC")
            }
        }
    }
}

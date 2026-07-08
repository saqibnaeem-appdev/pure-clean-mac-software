import Foundation
import Observation
import IOKit.ps
import Darwin

/// Publishes a fresh `SystemSnapshot` every second — CPU, RAM, disk,
/// network throughput and battery health. Pure read-only system queries.
@MainActor
@Observable
final class SystemStatsManager {

    private(set) var snapshot = SystemSnapshot()
    /// Rolling history for the Monitor charts (last 60 seconds).
    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []

    private var timer: Timer?
    private var previousCPUTicks: (used: UInt64, total: UInt64)?
    private var previousNet: (rx: UInt64, tx: UInt64, at: Date)?

    func start() {
        guard timer == nil else { return }
        snapshot.smartStatus = Self.readSMARTStatus()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        var snap = snapshot
        snap.cpuUsage = readCPU()
        snap.memory = Self.readMemory()
        (snap.diskTotal, snap.diskFree) = Self.readDisk()
        (snap.networkInPerSec, snap.networkOutPerSec) = readNetworkRate()
        snap.battery = Self.readBattery()
        snapshot = snap

        cpuHistory.append(snap.cpuUsage)
        memHistory.append(snap.memory.usedFraction)
        if cpuHistory.count > 60 { cpuHistory.removeFirst() }
        if memHistory.count > 60 { memHistory.removeFirst() }
    }

    // MARK: - CPU

    private func readCPU() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle

        defer { previousCPUTicks = (used, total) }
        guard let previous = previousCPUTicks else { return 0 }
        let dUsed = Double(used &- previous.used)
        let dTotal = Double(total &- previous.total)
        return dTotal > 0 ? min(1, max(0, dUsed / dTotal)) : 0
    }

    // MARK: - Memory

    static func readMemory() -> MemoryStats {
        var stats = MemoryStats()
        stats.total = Int64(ProcessInfo.processInfo.physicalMemory)

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vm = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return stats }

        let pageSize = Int64(vm_kernel_page_size)
        stats.active = Int64(vm.active_count) * pageSize
        stats.inactive = Int64(vm.inactive_count) * pageSize
        stats.wired = Int64(vm.wire_count) * pageSize
        stats.compressed = Int64(vm.compressor_page_count) * pageSize
        // "Used" the way Activity Monitor shows it: active + wired + compressed.
        stats.used = stats.active + stats.wired + stats.compressed
        return stats
    }

    // MARK: - Disk

    static func readDisk() -> (total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (total, free)
    }

    // MARK: - Network

    private func readNetworkRate() -> (rx: Int64, tx: Int64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var rx: UInt64 = 0, tx: UInt64 = 0
        var cursor = addrs
        while let current = cursor {
            let ifa = current.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let dataPtr = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if !name.hasPrefix("lo") {
                    let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                    rx &+= UInt64(data.ifi_ibytes)
                    tx &+= UInt64(data.ifi_obytes)
                }
            }
            cursor = ifa.ifa_next
        }

        let now = Date()
        defer { previousNet = (rx, tx, now) }
        guard let previous = previousNet else { return (0, 0) }
        let seconds = max(0.25, now.timeIntervalSince(previous.at))
        let dRx = Double(rx &- previous.rx) / seconds
        let dTx = Double(tx &- previous.tx) / seconds
        return (Int64(max(0, dRx)), Int64(max(0, dTx)))
    }

    // MARK: - Battery

    static func readBattery() -> BatteryStats {
        var stats = BatteryStats()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { return stats }

        stats.hasBattery = true
        stats.percentage = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        stats.isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false

        // Cycle count + health from the smart battery registry entry.
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            func intProp(_ key: String) -> Int? {
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int
            }
            stats.cycleCount = intProp("CycleCount") ?? 0
            if let design = intProp("DesignCapacity"),
               let max = intProp("AppleRawMaxCapacity") ?? intProp("MaxCapacity"),
               design > 0 {
                stats.healthPercent = Int((Double(max) / Double(design) * 100).rounded())
            }
        }
        return stats
    }

    // MARK: - Disk health (SMART)

    static func readSMARTStatus() -> String {
        let result = ShellRunner.run("/usr/sbin/diskutil", ["info", "/"])
        guard result.status == 0 else { return "—" }
        for line in result.output.split(separator: "\n")
        where line.contains("SMART Status") {
            return line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "—"
        }
        return "—"
    }
}

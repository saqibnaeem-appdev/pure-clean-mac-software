import Foundation
import Observation
import IOKit
import IOKit.ps
import CoreWLAN
import Metal
import Darwin

/// Publishes a fresh `SystemSnapshot` every second: CPU (total, per core,
/// load), memory (pressure, swap, cached files), disk capacity + I/O rates,
/// network throughput + interface details, GPU, battery internals and SMC
/// sensors. Everything is read from native APIs — nothing is estimated.
@MainActor
@Observable
final class SystemMonitor {

    private(set) var snapshot = SystemSnapshot()

    /// Rolling 60-sample histories driving the charts (1 sample/second).
    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var netInHistory: [Double] = []
    private(set) var netOutHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []

    private var timer: Timer?
    private var tickCount = 0
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousCoreTicks: [[UInt64]] = []
    private var previousNet: (rx: UInt64, tx: UInt64, at: Date)?
    private var previousDiskIO: (read: UInt64, written: UInt64, at: Date)?
    private var sensorsWarmedUp = false

    func start() {
        guard timer == nil else { return }

        var snap = snapshot
        snap.cpu.brand = Self.sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        snap.cpu.performanceCores = Self.sysctlInt("hw.perflevel0.physicalcpu")
            ?? Self.sysctlInt("hw.physicalcpu") ?? 0
        snap.cpu.efficiencyCores = Self.sysctlInt("hw.perflevel1.physicalcpu") ?? 0
        if let hz = Self.sysctlInt64("hw.cpufrequency_max") {
            snap.cpu.frequencyMHz = Int(hz / 1_000_000)
        }
        snap.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        snap.gpu.name = MTLCreateSystemDefaultDevice()?.name ?? "—"
        snapshot = snap

        // SMC key enumeration and `diskutil` are the two slow bits — do them
        // once, off the main thread, then let the regular ticks take over.
        Task.detached(priority: .utility) {
            _ = SMCService.shared.fanCount
            let smart = Self.readSMARTStatus()
            await MainActor.run { [weak self] in
                self?.snapshot.smartStatus = smart
                self?.sensorsWarmedUp = true
            }
        }

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Tick

    private func tick() {
        tickCount += 1
        var snap = snapshot

        (snap.cpu.usage, snap.cpu.userUsage, snap.cpu.systemUsage) = readCPUTotals()
        snap.cpu.perCore = readPerCoreUsage()
        snap.cpu.loadAverage = Self.readLoadAverage()
        snap.memory = Self.readMemory()
        (snap.network.inPerSec, snap.network.outPerSec) = readNetworkRate()
        snap.diskIO = readDiskIORate()
        snap.uptime = ProcessInfo.processInfo.systemUptime

        // Slower-moving values refresh every 3 seconds.
        if tickCount % 3 == 1 {
            snap.disk = DiskService.readOverview()
            snap.battery = Self.readBattery()
            snap.gpu = readGPU(existing: snap.gpu)
            let info = Self.readNetworkInfo()
            snap.network.interfaceName = info.name
            snap.network.ipAddress = info.ip
            snap.network.wifiSSID = info.ssid
            snap.network.wifiRSSI = info.rssi
            snap.network.wifiTxRateMbps = info.txRate
            if sensorsWarmedUp {
                snap.sensors = Self.readSensors()
            }
        }

        snapshot = snap

        appendHistory(&cpuHistory, snap.cpu.usage)
        appendHistory(&memHistory, snap.memory.usedFraction)
        appendHistory(&netInHistory, Double(snap.network.inPerSec))
        appendHistory(&netOutHistory, Double(snap.network.outPerSec))
        appendHistory(&diskReadHistory, Double(snap.diskIO.readPerSec))
        appendHistory(&diskWriteHistory, Double(snap.diskIO.writePerSec))
    }

    private func appendHistory(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > 60 { history.removeFirst(history.count - 60) }
    }

    // MARK: - CPU

    private func readCPUTotals() -> (total: Double, user: Double, system: Double) {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0) }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        defer { previousCPUTicks = (user, system, idle, nice) }
        guard let prev = previousCPUTicks else { return (0, 0, 0) }

        let dUser = Double(user &- prev.user) + Double(nice &- prev.nice)
        let dSystem = Double(system &- prev.system)
        let dIdle = Double(idle &- prev.idle)
        let dTotal = dUser + dSystem + dIdle
        guard dTotal > 0 else { return (0, 0, 0) }
        return (min(1, (dUser + dSystem) / dTotal), dUser / dTotal, dSystem / dTotal)
    }

    private func readPerCoreUsage() -> [Double] {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt64]] = []
        current.reserveCapacity(Int(coreCount))
        for core in 0..<Int(coreCount) {
            var ticks: [UInt64] = []
            for state in 0..<states {
                ticks.append(UInt64(UInt32(bitPattern: info[core * states + state])))
            }
            current.append(ticks)
        }

        defer { previousCoreTicks = current }
        guard previousCoreTicks.count == current.count else {
            return Array(repeating: 0, count: current.count)
        }

        return current.enumerated().map { core, ticks in
            let prev = previousCoreTicks[core]
            let dUser = Double(ticks[Int(CPU_STATE_USER)] &- prev[Int(CPU_STATE_USER)])
            let dSystem = Double(ticks[Int(CPU_STATE_SYSTEM)] &- prev[Int(CPU_STATE_SYSTEM)])
            let dNice = Double(ticks[Int(CPU_STATE_NICE)] &- prev[Int(CPU_STATE_NICE)])
            let dIdle = Double(ticks[Int(CPU_STATE_IDLE)] &- prev[Int(CPU_STATE_IDLE)])
            let total = dUser + dSystem + dNice + dIdle
            return total > 0 ? min(1, max(0, (dUser + dSystem + dNice) / total)) : 0
        }
    }

    private static func readLoadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : 0
    }

    // MARK: - Memory

    static func readMemory() -> MemoryStats {
        var stats = MemoryStats()
        stats.total = Int64(ProcessInfo.processInfo.physicalMemory)

        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vm = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return stats }

        let pageSize = Int64(vm_kernel_page_size)
        // The same arithmetic Activity Monitor uses:
        //   App Memory  = internal pages − purgeable
        //   Memory Used = app + wired + compressed
        //   Cached Files = file-backed (external) + purgeable
        stats.appMemory = max(0, Int64(vm.internal_page_count) - Int64(vm.purgeable_count)) * pageSize
        stats.wired = Int64(vm.wire_count) * pageSize
        stats.compressed = Int64(vm.compressor_page_count) * pageSize
        stats.used = stats.appMemory + stats.wired + stats.compressed
        stats.cached = (Int64(vm.external_page_count) + Int64(vm.purgeable_count)) * pageSize

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            stats.swapUsed = Int64(swap.xsu_used)
            stats.swapTotal = Int64(swap.xsu_total)
        }

        var pressureLevel: Int32 = 1
        var pressureSize = MemoryLayout<Int32>.stride
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &pressureSize, nil, 0) == 0 {
            stats.pressure = MemoryPressure(rawValue: Int(pressureLevel)) ?? .normal
        }
        return stats
    }

    // MARK: - Disk I/O

    private func readDiskIORate() -> DiskIOStats {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator) == kIOReturnSuccess else { return snapshot.diskIO }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, written: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            guard let statistics = IORegistryEntryCreateCFProperty(
                entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            read &+= (statistics["Bytes (Read)"] as? UInt64) ?? 0
            written &+= (statistics["Bytes (Written)"] as? UInt64) ?? 0
        }

        let now = Date()
        defer { previousDiskIO = (read, written, now) }
        guard let prev = previousDiskIO else { return DiskIOStats() }
        let seconds = max(0.25, now.timeIntervalSince(prev.at))
        return DiskIOStats(
            readPerSec: Int64(max(0, Double(read &- prev.read) / seconds)),
            writePerSec: Int64(max(0, Double(written &- prev.written) / seconds)))
    }

    // MARK: - Network

    /// Reads the kernel's 64-bit per-interface byte counters (NET_RT_IFLIST2)
    /// and only counts physical `en*` interfaces — so peer-to-peer (awdl),
    /// VPN tunnels (utun) and bridges don't inflate the number, and the
    /// counters can't wrap the way the 32-bit `getifaddrs` ones do.
    private func readNetworkRate() -> (rx: Int64, tx: Int64) {
        // CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2 (6), 0
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, 6, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return (0, 0)
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return (0, 0)
        }

        var rx: UInt64 = 0, tx: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }

                // RTM_IFINFO2 (0x12) carries the 64-bit if_data64 statistics.
                if header.ifm_type == 0x12,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if_indextoname(UInt32(info.ifm_index), &name)
                    if String(cString: name).hasPrefix("en") {
                        rx &+= info.ifm_data.ifi_ibytes
                        tx &+= info.ifm_data.ifi_obytes
                    }
                }
                offset += messageLength
            }
        }

        let now = Date()
        defer { previousNet = (rx, tx, now) }
        guard let previous = previousNet, rx >= previous.rx, tx >= previous.tx else {
            return (0, 0)
        }
        let seconds = max(0.25, now.timeIntervalSince(previous.at))
        let dRx = Double(rx - previous.rx) / seconds
        let dTx = Double(tx - previous.tx) / seconds
        return (Int64(max(0, dRx)), Int64(max(0, dTx)))
    }

    private static func readNetworkInfo()
        -> (name: String, ip: String, ssid: String?, rssi: Int?, txRate: Double?) {
        var name = "—", ip = "—"

        var addrs: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addrs) == 0 {
            defer { freeifaddrs(addrs) }
            var best: (name: String, ip: String)?
            var cursor = addrs
            while let current = cursor {
                let ifa = current.pointee
                cursor = ifa.ifa_next

                guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
                let flags = Int32(ifa.ifa_flags)
                guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
                let ifName = String(cString: ifa.ifa_name)
                guard !ifName.hasPrefix("utun"), !ifName.hasPrefix("awdl"),
                      !ifName.hasPrefix("llw"), !ifName.hasPrefix("bridge") else { continue }

                var sockaddr = addr.pointee
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(&sockaddr, socklen_t(sockaddr.sa_len),
                               &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: host)
                    // Prefer the primary "en" interface; keep the first hit otherwise.
                    if ifName.hasPrefix("en") {
                        best = (ifName, address)
                        break
                    }
                    if best == nil { best = (ifName, address) }
                }
            }
            if let best {
                name = best.name
                ip = best.ip
            }
        }

        var ssid: String?, rssi: Int?, txRate: Double?
        if let wifi = CWWiFiClient.shared().interface(), wifi.powerOn() {
            ssid = wifi.ssid()  // nil unless the app has location authority — shown as "Wi-Fi" then
            let signal = wifi.rssiValue()
            if signal < 0 { rssi = signal }
            let rate = wifi.transmitRate()
            if rate > 0 { txRate = rate }
            if name == "—", let wifiName = wifi.interfaceName { name = wifiName }
        }
        return (name, ip, ssid, rssi, txRate)
    }

    // MARK: - GPU

    private func readGPU(existing: GPUStats) -> GPUStats {
        var stats = existing
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator) == kIOReturnSuccess else { return stats }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            guard let perf = IORegistryEntryCreateCFProperty(
                entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }

            if let utilization = perf["Device Utilization %"] as? Int
                ?? perf["GPU Activity(%)"] as? Int {
                stats.utilization = min(1, max(0, Double(utilization) / 100))
                stats.available = true
            }
            if let inUse = perf["In use system memory"] as? Int64 {
                stats.memoryUsed = inUse
                stats.available = true
            } else if let inUse = perf["In use system memory"] as? Int {
                stats.memoryUsed = Int64(inUse)
                stats.available = true
            }
            if stats.available { break }
        }
        return stats
    }

    // MARK: - Sensors (SMC)

    private static func readSensors() -> SensorStats {
        let smc = SMCService.shared
        var sensors = SensorStats()
        guard smc.isAvailable else { return sensors }
        sensors.fanCount = smc.fanCount
        sensors.fans = smc.fanSpeeds()
        sensors.cpuTemperature = smc.cpuTemperature()
        sensors.gpuTemperature = smc.gpuTemperature()
        return sensors
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
        let state = info[kIOPSPowerSourceStateKey] as? String
        stats.isPluggedIn = state == kIOPSACPowerValue
        stats.powerSource = stats.isPluggedIn ? "Power Adapter" : "Battery"
        if let minutes = info[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
            stats.timeToEmptyMinutes = minutes
        }
        if let minutes = info[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
            stats.timeToFullMinutes = minutes
        }

        let entry = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            func property(_ key: String) -> Int? {
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int
            }
            stats.cycleCount = property("CycleCount") ?? 0
            stats.designCapacitymAh = property("DesignCapacity") ?? 0
            stats.maxCapacitymAh = property("AppleRawMaxCapacity")
                ?? property("NominalChargeCapacity") ?? 0
            stats.currentCapacitymAh = property("AppleRawCurrentCapacity") ?? 0
            if let raw = property("Temperature"), raw > 0 {
                stats.temperature = Double(raw) / 100.0
            }
            if stats.designCapacitymAh > 0, stats.maxCapacitymAh > 0 {
                stats.healthPercent = Int(
                    (Double(stats.maxCapacitymAh) / Double(stats.designCapacitymAh) * 100).rounded())
            }
        }
        return stats
    }

    // MARK: - Disk health (SMART)

    nonisolated static func readSMARTStatus() -> String {
        let result = ShellRunner.run("/usr/sbin/diskutil", ["info", "/"])
        guard result.status == 0 else { return "—" }
        for line in result.output.split(separator: "\n")
        where line.contains("SMART Status") {
            return line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "—"
        }
        return "—"
    }

    // MARK: - sysctl helpers

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func sysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.stride
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

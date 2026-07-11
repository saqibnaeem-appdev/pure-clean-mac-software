import Foundation
import IOKit

/// Minimal Apple SMC client used to read fan speeds and temperature sensors.
///
/// Sensor keys differ per Mac model (and Apple Silicon generations expose a
/// different set than Intel), so instead of hard-coding one list we enumerate
/// every key the SMC publishes once at startup and then read the temperature
/// families we recognise. When the SMC exposes nothing useful (VMs, future
/// hardware) every accessor returns nil/empty and the UI says "not available"
/// — never a fake number.
final class SMCService {

    static let shared = SMCService()

    private var connection: io_connect_t = 0
    private(set) var isAvailable = false
    /// All four-character keys published by this machine's SMC.
    private var allKeys: Set<String> = []
    private var cpuTempKeys: [String] = []
    private var gpuTempKeys: [String] = []

    // MARK: - Raw structs (layout must match the kernel's SMCParamStruct)

    private struct SMCVersion {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Selector: UInt8 {
        case readKey = 5
        case getKeyFromIndex = 8
        case getKeyInfo = 9
    }

    // MARK: - Lifecycle

    private init() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return
        }
        isAvailable = true
        enumerateKeys()

        // Temperature families: Tp/Te/Tf cover Apple Silicon CPU cluster
        // sensors, TC?P/TC?D the Intel ones; Tg/TG are GPU.
        cpuTempKeys = allKeys.filter {
            $0.hasPrefix("Tp") || $0.hasPrefix("Te") || $0.hasPrefix("Tf")
                || $0 == "TC0P" || $0 == "TC0D" || $0 == "TC0E" || $0 == "TC0F"
        }.sorted()
        gpuTempKeys = allKeys.filter { $0.hasPrefix("Tg") || $0 == "TG0P" || $0 == "TG0D" }
            .sorted()
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Public readings

    var fanCount: Int {
        guard isAvailable, let value = readValue("FNum") else { return 0 }
        return Int(value)
    }

    func fanSpeeds() -> [FanReading] {
        guard isAvailable else { return [] }
        return (0..<fanCount).compactMap { index in
            guard let rpm = readValue("F\(index)Ac"), rpm >= 0, rpm < 20_000 else { return nil }
            return FanReading(id: index, rpm: Int(rpm))
        }
    }

    /// Average of the plausible CPU cluster/die sensors, in °C.
    func cpuTemperature() -> Double? {
        averageTemperature(of: cpuTempKeys)
    }

    func gpuTemperature() -> Double? {
        averageTemperature(of: gpuTempKeys)
    }

    private func averageTemperature(of keys: [String]) -> Double? {
        guard isAvailable else { return nil }
        let readings = keys.compactMap(readValue).filter { $0 > 5 && $0 < 115 }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    // MARK: - Key plumbing

    private func enumerateKeys() {
        guard let countValue = readValue("#KEY") else { return }
        let count = Int(countValue)
        guard count > 0, count < 16_384 else { return }

        for index in 0..<count {
            var input = SMCParamStruct()
            input.data8 = Selector.getKeyFromIndex.rawValue
            input.data32 = UInt32(index)
            guard let output = call(input), output.result == 0 else { continue }
            allKeys.insert(Self.stringFromKey(output.key))
        }
    }

    /// Reads any SMC key and decodes it to a Double when the type is numeric.
    private func readValue(_ key: String) -> Double? {
        guard connection != 0 else { return nil }
        let keyCode = Self.keyFromString(key)

        var infoInput = SMCParamStruct()
        infoInput.key = keyCode
        infoInput.data8 = Selector.getKeyInfo.rawValue
        guard let info = call(infoInput), info.result == 0 else { return nil }

        var readInput = SMCParamStruct()
        readInput.key = keyCode
        readInput.keyInfo = info.keyInfo
        readInput.data8 = Selector.readKey.rawValue
        guard let output = call(readInput), output.result == 0 else { return nil }

        let type = Self.stringFromKey(info.keyInfo.dataType)
        let bytes = Mirror(reflecting: output.bytes).children.compactMap { $0.value as? UInt8 }
        return Self.decode(bytes: bytes, type: type, size: Int(info.keyInfo.dataSize))
    }

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, 2 /* kSMCHandleYPCEvent */,
            &input, MemoryLayout<SMCParamStruct>.stride,
            &output, &outputSize)
        return result == kIOReturnSuccess ? output : nil
    }

    private static func decode(bytes: [UInt8], type: String, size: Int) -> Double? {
        guard bytes.count >= 4, size > 0 else { return nil }
        switch type {
        case "flt ":
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "fpe2":
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        case "sp78":
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "ui8 ":
            return Double(bytes[0])
        case "ui16":
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            let raw = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return Double(raw)
        default:
            return nil
        }
    }

    private static func keyFromString(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func stringFromKey(_ key: UInt32) -> String {
        let scalars = [24, 16, 8, 0].map { shift -> Character in
            let byte = UInt8((key >> UInt32(shift)) & 0xFF)
            return Character(UnicodeScalar(byte))
        }
        return String(scalars)
    }
}

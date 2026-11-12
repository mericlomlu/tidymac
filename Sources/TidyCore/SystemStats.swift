import Foundation
import IOKit.ps

public struct MemoryStats: Sendable {
    public let total: UInt64, used: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, free: UInt64
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    /// Cached files and anything else not counted as app, wired, compressed or free.
    public var other: UInt64 {
        let counted = app + wired + compressed + free
        return total > counted ? total - counted : 0
    }
}

public struct ProcessInfoRow: Identifiable, Sendable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let rssBytes: UInt64
    public let cpu: Double
}

public struct BatteryStats: Sendable { public let percent: Int; public let charging: Bool }

/// Reads live system numbers. Not thread-safe (keeps the previous CPU sample); use from one actor.
public final class SystemSampler {
    private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    public init() {}

    public func memory() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vm = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size) }
        }
        guard kr == KERN_SUCCESS else { return MemoryStats(total: total, used: 0, app: 0, wired: 0, compressed: 0, free: total) }
        let page = UInt64(getpagesize())
        let free = UInt64(vm.free_count) * page
        let wired = UInt64(vm.wire_count) * page
        let compressed = UInt64(vm.compressor_page_count) * page
        let app = UInt64(vm.internal_page_count &- vm.purgeable_count) * page
        let used = min(total, app + wired + compressed)   // Activity Monitor's "Memory Used"
        return MemoryStats(total: total, used: used, app: app, wired: wired, compressed: compressed, free: free)
    }

    /// CPU busy fraction (0…1) since the previous call; first call returns 0.
    public func cpuUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let t = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { lastTicks = t }
        guard let p = lastTicks else { return 0 }
        let busy = Double((t.user &- p.user) &+ (t.system &- p.system) &+ (t.nice &- p.nice))
        let idle = Double(t.idle &- p.idle)
        return busy + idle == 0 ? 0 : busy / (busy + idle)
    }

    public func disk(at url: URL = URL(fileURLWithPath: "/")) -> (free: Int64, total: Int64) {
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }

    public func battery() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryStats(percent: cur * 100 / max, charging: (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return nil
    }

    /// Top processes by resident memory, via `ps`.
    public func topProcesses(limit: Int = 10) -> [ProcessInfoRow] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,rss=,pcpu=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Self.parsePS(String(decoding: data, as: UTF8.self), limit: limit)
    }

    static func parsePS(_ text: String, limit: Int) -> [ProcessInfoRow] {
        var rows: [ProcessInfoRow] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let rss = UInt64(parts[1]), let cpu = Double(parts[2]) else { continue }
            let name = (String(parts[3]) as NSString).lastPathComponent
            rows.append(ProcessInfoRow(pid: pid, name: name, rssBytes: rss * 1024, cpu: cpu))
        }
        return Array(rows.sorted { $0.rssBytes > $1.rssBytes }.prefix(limit))
    }
}

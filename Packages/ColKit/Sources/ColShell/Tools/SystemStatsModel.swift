import Darwin
import Foundation
import ColCore
import Observation

/// Processor, memory, network and disk, sampled once a second only while the System page is on screen.
@MainActor
@Observable
final class SystemStatsModel {
    private(set) var cpu: Double = 0
    private(set) var memoryUsed: Double = 0
    private(set) var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    private(set) var download: Double = 0
    private(set) var upload: Double = 0
    private(set) var diskFree: Double = 0
    private(set) var diskTotal: Double = 0
    /// Recent processor load, for the sparkline.
    private(set) var cpuHistory: [Double] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks: [[UInt64]] = []
    @ObservationIgnored private var bytes: (in: UInt64, out: UInt64, at: Date)?
    @ObservationIgnored private var watchers = 0

    /// Pages call these as they appear and disappear; sampling runs only while one is watching.
    func startWatching() {
        watchers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let now = Self.cpuTicks()
        if !ticks.isEmpty {
            cpu = SystemMath.cpuUsage(previous: ticks, current: now)
            cpuHistory.append(cpu)
            if cpuHistory.count > 30 { cpuHistory.removeFirst(cpuHistory.count - 30) }
        }
        ticks = now
        memoryUsed = Self.memoryUsed()
        let counters = Self.networkBytes()
        let date = Date()
        if let previous = bytes {
            let seconds = date.timeIntervalSince(previous.at)
            download = SystemMath.rate(from: previous.in, to: counters.in, over: seconds)
            upload = SystemMath.rate(from: previous.out, to: counters.out, over: seconds)
        }
        bytes = (counters.in, counters.out, date)
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            diskTotal = Double(values.volumeTotalCapacity ?? 0)
        }
    }

    private static func cpuTicks() -> [[UInt64]] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        return (0..<Int(count)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            // Order: user, system, idle, nice.
            return [CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE].map { UInt64(UInt32(bitPattern: info[base + Int($0)])) }
        }
    }

    /// Memory in use as Activity Monitor counts it: app memory, wired and compressed.
    private static func memoryUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Double(getpagesize())
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        return (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    private static func networkBytes() -> (in: UInt64, out: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }
        var received: UInt64 = 0, sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let name = String(cString: entry.pointee.ifa_name)
            if entry.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"),
               let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                received += UInt64(data.pointee.ifi_ibytes)
                sent += UInt64(data.pointee.ifi_obytes)
            }
            cursor = entry.pointee.ifa_next
        }
        return (received, sent)
    }
}

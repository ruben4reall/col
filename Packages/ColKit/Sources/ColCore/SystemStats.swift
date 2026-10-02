import Foundation

/// Rates and percentages from raw counters, kept pure so they are tested.
public enum SystemMath {
    /// CPU busy share between two samples of per-core ticks (user, system, idle, nice).
    public static func cpuUsage(previous: [[UInt64]], current: [[UInt64]]) -> Double {
        var busy: UInt64 = 0, total: UInt64 = 0
        for (old, new) in zip(previous, current) where old.count == 4 && new.count == 4 {
            let delta = zip(old, new).map { $1 &- $0 }
            busy += delta[0] + delta[1] + delta[3]
            total += delta.reduce(0, +)
        }
        return total > 0 ? Double(busy) / Double(total) : 0
    }

    /// Bytes per second between two counter readings; counters that went backwards (an interface reset) count as 0.
    public static func rate(from old: UInt64, to new: UInt64, over seconds: Double) -> Double {
        guard seconds > 0, new >= old else { return 0 }
        return Double(new - old) / seconds
    }

    /// "1.2 MB/s", "340 KB/s", "0 KB/s": decimal units, like Activity Monitor.
    public static func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
    }

    /// Memory in binary units, as Apple sells and reports it: 18 GB of RAM is 18 × 2³⁰ bytes.
    public static func formatMemory(_ bytes: Double) -> String {
        let gigabytes = bytes / 1_073_741_824
        return String(format: gigabytes >= 100 || gigabytes.rounded() == gigabytes ? "%.0f GB" : "%.1f GB", gigabytes)
    }

    public static func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000_000 { return String(format: "%.1f TB", bytes / 1_000_000_000_000) }
        if bytes >= 1_000_000_000 { return String(format: bytes >= 100_000_000_000 ? "%.0f GB" : "%.1f GB", bytes / 1_000_000_000) }
        return String(format: "%.0f MB", bytes / 1_000_000)
    }
}

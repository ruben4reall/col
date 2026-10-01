import Testing
@testable import ColCore

struct SystemMathTests {
    @Test func cpuUsageAcrossCores() {
        let before: [[UInt64]] = [[100, 50, 800, 50], [0, 0, 1000, 0]]
        let after: [[UInt64]] = [[150, 70, 850, 50], [30, 10, 1060, 0]]
        // Busy: (50+20+0) + (30+10+0) = 110 of (120 + 100) = 220.
        #expect(SystemMath.cpuUsage(previous: before, current: after) == 0.5)
        #expect(SystemMath.cpuUsage(previous: [], current: []) == 0)
    }

    @Test func ratesIgnoreResets() {
        #expect(SystemMath.rate(from: 1_000, to: 3_000, over: 2) == 1_000)
        #expect(SystemMath.rate(from: 5_000, to: 10, over: 1) == 0)
    }

    @Test func formats() {
        #expect(SystemMath.formatRate(1_250_000) == "1.2 MB/s" || SystemMath.formatRate(1_250_000) == "1.3 MB/s")
        #expect(SystemMath.formatRate(340_000) == "340 KB/s")
        #expect(SystemMath.formatBytes(18_000_000_000) == "18.0 GB")
        #expect(SystemMath.formatBytes(312_000_000_000) == "312 GB")
        #expect(SystemMath.formatBytes(2_500_000_000_000) == "2.5 TB")
        #expect(SystemMath.formatMemory(18 * 1_073_741_824) == "18 GB")
        #expect(SystemMath.formatMemory(15.24 * 1_073_741_824) == "15.2 GB")
    }
}

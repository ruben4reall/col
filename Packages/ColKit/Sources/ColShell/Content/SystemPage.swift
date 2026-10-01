import ColCore
import SwiftUI

/// The Mac at a glance. Sampling runs only while this page is visible.
struct SystemPage: View {
    let stats: SystemStatsModel

    var body: some View {
        HStack(spacing: 10) {
            Gauge(
                title: Text("Processor", bundle: .module),
                fraction: stats.cpu,
                value: stats.cpu.formatted(.percent.precision(.fractionLength(0))),
                detail: nil,
                tint: Theme.accent,
                history: stats.cpuHistory
            )
            Gauge(
                title: Text("Memory", bundle: .module),
                fraction: stats.memoryTotal > 0 ? stats.memoryUsed / stats.memoryTotal : 0,
                value: SystemMath.formatMemory(stats.memoryUsed),
                detail: SystemMath.formatMemory(stats.memoryTotal),
                tint: RGBA.purple.color,
                history: nil
            )
            Gauge(
                title: Text("Disk", bundle: .module),
                fraction: stats.diskTotal > 0 ? 1 - stats.diskFree / stats.diskTotal : 0,
                value: SystemMath.formatBytes(stats.diskFree),
                detail: String(localized: "free", bundle: .module),
                tint: RGBA.blue.color,
                history: nil
            )
            VStack(alignment: .leading, spacing: 7) {
                Text("Network", bundle: .module)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Label(SystemMath.formatRate(stats.download), systemImage: "arrow.down")
                    .foregroundStyle(.white)
                Label(SystemMath.formatRate(stats.upload), systemImage: "arrow.up")
                    .foregroundStyle(Theme.secondaryText)
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.fill))
        }
        .onAppear { stats.startWatching() }
        .onDisappear { stats.stopWatching() }
    }
}

private struct Gauge: View {
    let title: Text
    let fraction: Double
    let value: String
    let detail: String?
    let tint: Color
    let history: [Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: value)
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer(minLength: 0)
            if let history, history.count > 1 {
                Sparkline(values: history, tint: tint).frame(height: 18)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(tint).frame(width: max(4, geometry.size.width * min(max(fraction, 0), 1)))
                    }
                }
                .frame(height: 5)
                .animation(.spring(duration: 0.5, bounce: 0), value: fraction)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.fill))
    }
}

private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: geometry.size.height * (1 - CGFloat(min(max(value, 0), 1)))
                )
            }
            ZStack {
                Path { path in
                    path.addLines(points)
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in path.addLines(points) }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(tint).frame(width: 4, height: 4).position(last)
                }
            }
        }
    }
}

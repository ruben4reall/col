import IsletCore
import Observation
import SwiftUI

@MainActor
@Observable
final class DeviceCardModel {
    var name = ""
    var symbol = "airpodspro"
    var model: HeadphoneModel?
    var battery: AccessoryBattery?
    /// Changes each time a device connects, to replay the entrance.
    var arrival = 0
}

/// The card the island opens when headphones connect: the device, its name and its battery.
struct DeviceCardView: View {
    let model: DeviceCardModel
    @State private var shown = false
    /// The turn the headphones make as they arrive: a full revolution that slows to face you.
    @State private var turn: Double = 0

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: model.symbol)
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(.white, .white.opacity(0.55))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 100, height: 90)
                .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                .scaleEffect(shown ? 1 : 0.55)
                .opacity(shown ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Connected", bundle: .module)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            if let battery = model.battery {
                HStack(spacing: 14) {
                    if let left = battery.left { BatteryRing(level: left, label: "L") }
                    if let right = battery.right { BatteryRing(level: right, label: "R") }
                    if let single = battery.single, battery.left == nil { BatteryRing(level: single, label: nil) }
                    if let caseLevel = battery.caseLevel { BatteryRing(level: caseLevel, label: nil, symbol: "case.fill") }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: model.battery)
        .onAppear(perform: arrive)
        .onChange(of: model.arrival) { arrive() }
    }

    /// Scales in while turning once around, fast at first, then settling facing forward. Over-ear headphones turn a
    /// little slower, as heavier things do.
    private func arrive() {
        shown = false
        turn = -360
        withAnimation(.spring(duration: 0.7, bounce: 0.3)) { shown = true }
        withAnimation(.timingCurve(0.15, 0.7, 0.25, 1, duration: model.model?.isOverEar == true ? 1.9 : 1.6)) { turn = 0 }
    }
}

private struct BatteryRing: View {
    let level: Int
    let label: String?
    var symbol: String?

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(color.opacity(0.22), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                } else if let label {
                    Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 36, height: 36)
            Text(verbatim: "\(level) %")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var color: Color { level <= 20 ? RGBA.red.color : RGBA.green.color }
}

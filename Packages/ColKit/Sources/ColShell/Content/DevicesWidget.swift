import ColCore
import SwiftUI

/// The accessories of the Mac with their battery: mice, keyboards, trackpads, game controllers.
struct DevicesWidget: View {
    let accessories: AccessoryBatteries
    let width: WidgetWidth

    var body: some View {
        Group {
            if !Preferences.showsAccessoryBatteries {
                empty(title: Text("Accessories are off", bundle: .module), detail: Text("Turn them on in Settings, Live activities.", bundle: .module))
            } else if accessories.levels.isEmpty {
                empty(title: Text("No accessories", bundle: .module), detail: Text("Mice, keyboards and trackpads show here with their battery.", bundle: .module))
            } else if width == .full {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 6) {
                    ForEach(accessories.levels.prefix(6)) { AccessoryRow(level: $0) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(accessories.levels.prefix(3)) { AccessoryRow(level: $0) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { if Preferences.showsAccessoryBatteries { accessories.refresh() } }
    }

    private func empty(title: Text, detail: Text) -> some View {
        VStack(spacing: 5) {
            Image(systemName: "magicmouse.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            title
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
            detail
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One accessory: its symbol, its name, and its battery as a figure and a small gauge, red when low.
private struct AccessoryRow: View {
    let level: AccessoryLevel

    var body: some View {
        let low = level.percent < LowBatteryWatch.threshold
        let tint = low ? RGBA.red.color : (level.percent <= 30 ? RGBA.orange.color : RGBA.green.color)
        HStack(spacing: 10) {
            Image(systemName: level.kind.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.fill))
            Text(verbatim: level.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text((Double(level.percent) / 100).formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(low ? tint : Theme.secondaryText)
                .fixedSize()
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                    .frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: max(2, 18 * CGFloat(level.percent) / 100), height: 7)
                    .padding(.leading, 2)
            }
        }
        .frame(height: 28)
    }
}

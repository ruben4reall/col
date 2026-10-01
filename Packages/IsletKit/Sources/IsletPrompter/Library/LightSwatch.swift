import SwiftUI

/// A disc of the stage light's colours, ringed when chosen; a crossed disc for no light.
public struct LightSwatch: View {
    let light: StageLight
    let selected: Bool

    public init(light: StageLight, selected: Bool) {
        self.light = light
        self.selected = selected
    }

    public var body: some View {
        ZStack {
            if light == .off {
                Circle().fill(Color.primary.opacity(0.08))
                Image(systemName: "slash.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            } else {
                Circle().fill(AngularGradient(colors: light.stops.map { Color(red: $0.0, green: $0.1, blue: $0.2) }, center: .center))
                Circle().fill(Color.black).padding(7)
            }
        }
        .frame(width: 26, height: 26)
        .padding(3)
        .overlay(Circle().strokeBorder(selected ? Color.primary.opacity(0.85) : .clear, lineWidth: 2))
    }
}

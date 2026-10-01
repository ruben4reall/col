import AppKit
import Observation

/// Picks a colour anywhere on screen with the system sampler and keeps the last few.
@MainActor
@Observable
final class ColorPickerModel {
    private(set) var colors: [NSColor] = []
    private(set) var copied: NSColor?
    @ObservationIgnored private var sampler: NSColorSampler?

    func pick() {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            let picked = color
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let picked else { return }
                    self.colors.removeAll { Self.hex(of: $0) == Self.hex(of: picked) }
                    self.colors.insert(picked, at: 0)
                    if self.colors.count > 5 { self.colors.removeLast() }
                    self.copy(picked)
                    self.sampler = nil
                }
            }
        }
    }

    func copy(_ color: NSColor) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.hex(of: color), forType: .string)
        copied = color
    }

    static func hex(of color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        let value = { (component: CGFloat) in Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", value(rgb.redComponent), value(rgb.greenComponent), value(rgb.blueComponent))
    }
}

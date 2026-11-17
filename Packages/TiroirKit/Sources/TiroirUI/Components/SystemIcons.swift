import AppKit
import TiroirCore

/// Pictures for macOS's own icons, which have no app icon of their own in a drawer: a symbol on a neutral tile, the
/// way System Settings draws its panes.
@MainActor
public enum SystemIcons {
    private static var cache: [String: NSImage] = [:]

    /// The symbol for a Control Center module or an Apple agent.
    static func symbol(for id: IconID) -> String {
        let key = id.key.lowercased()
        let table: [(String, String)] = [
            ("wifi", "wifi"), ("battery", "battery.100"), ("sound", "speaker.wave.2.fill"), ("clock", "clock.fill"),
            ("bluetooth", "wave.3.right"), ("focus", "moon.fill"), ("display", "sun.max.fill"), ("nowplaying", "play.fill"),
            ("airdrop", "airplayaudio"), ("screenmirroring", "rectangle.on.rectangle"), ("controlcenter", "switch.2"),
            ("user", "person.crop.circle"), ("keyboard", "keyboard"), ("accessibility", "accessibility"),
            ("timemachine", "clock.arrow.circlepath"), ("vpn", "network.badge.shield.half.filled"),
            ("stagemanager", "rectangle.split.3x1"), ("bento", "switch.2"), ("weather", "cloud.sun.fill"),
        ]
        if let match = table.first(where: { key.contains($0.0) }) { return match.1 }
        switch id.bundleID {
        case "com.apple.Spotlight": return "magnifyingglass"
        case "com.apple.TextInputMenuAgent": return "keyboard"
        case "com.apple.Siri": return "waveform"
        default: return "circle.grid.2x2.fill"
        }
    }

    public static func image(for id: IconID) -> NSImage {
        let symbol = symbol(for: id)
        if let cached = cache[symbol] { return cached }
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 14, yRadius: 14)
            NSGradient(starting: NSColor(white: 0.34, alpha: 1), ending: NSColor(white: 0.2, alpha: 1))?.draw(in: tile, angle: -90)
            let configuration = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
                .applying(.init(paletteColors: [NSColor(white: 0.97, alpha: 1)]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let size = glyph.size
                glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
        cache[symbol] = image
        return image
    }
}

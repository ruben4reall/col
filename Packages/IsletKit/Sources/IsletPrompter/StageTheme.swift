import AppKit
import SwiftUI

/// The prompter's design tokens. The prompter is black like the notch it hangs from; its signature is stage light,
/// Islet's coral by default, which marks what belongs to the prompter: the light inside the notch, the next word, the
/// voice, the main button.
public enum StageTheme {
    /// Islet's coral, the accent: buttons, selection, the level meter.
    public static let accent = Color(red: 1, green: 0.478, blue: 0.349)
    public static let accentNS = NSColor(srgbRed: 1, green: 0.478, blue: 0.349, alpha: 1)
    /// The deep end of the coral, for gradients.
    public static let ember = Color(red: 0.886, green: 0.278, blue: 0.176)
    /// A light coral that reads well on black: the next word, figures on the prompter.
    public static let highlight = Color(red: 1, green: 0.78, blue: 0.66)
    public static let highlightNS = NSColor(srgbRed: 1, green: 0.78, blue: 0.66, alpha: 1)
    public static let stage = Color(red: 0.027, green: 0.027, blue: 0.031)

    /// The panels of the main window: near black in dark mode, white in light mode.
    public static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.075, green: 0.075, blue: 0.086, alpha: 1)
            : NSColor.white
    })

    /// The stage light inside the prompter and the halo beneath it, in the colour chosen in Settings (coral by
    /// default).
    static func lamp(_ light: StageLight) -> NSColor {
        let (red, green, blue) = light.lamp
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// The next word and the prompter's figures, in a light tint of the stage light.
    static func highlight(_ light: StageLight) -> NSColor {
        let (red, green, blue) = light.highlight
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    static func highlightColor(_ light: StageLight) -> Color {
        let (red, green, blue) = light.highlight
        return Color(red: red, green: green, blue: blue)
    }

    /// The two ends of the light, for the level meter and the swatches.
    static func lightEnds(_ light: StageLight) -> [Color] {
        let stops = light.stops
        return [Color(red: stops[0].0, green: stops[0].1, blue: stops[0].2), Color(red: stops[2].0, green: stops[2].1, blue: stops[2].2)]
    }

    // The system's label colours on a dark background.
    static let secondaryText = Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.6)
    static let tertiaryText = Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.32)
    static let fill = Color.white.opacity(0.1)
    static let raisedFill = Color.white.opacity(0.16)

    /// Colours of the prompter's text for each theme.
    struct Palette {
        let background: NSColor
        let text: NSColor
        let read: NSColor
        let heading: NSColor
        let cue: NSColor
        let band: NSColor
    }

    static func palette(_ theme: PrompterTheme) -> Palette {
        switch theme {
        case .night:
            Palette(background: .black, text: NSColor(white: 0.97, alpha: 1), read: NSColor(white: 0.97, alpha: 0.34),
                    heading: NSColor(white: 0.97, alpha: 0.5), cue: highlightNS.withAlphaComponent(0.8), band: NSColor(white: 1, alpha: 0.06))
        case .paper:
            Palette(background: NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1), text: NSColor(white: 0.08, alpha: 1),
                    read: NSColor(white: 0.08, alpha: 0.3), heading: NSColor(white: 0.08, alpha: 0.5),
                    cue: NSColor(srgbRed: 0.82, green: 0.32, blue: 0.2, alpha: 1), band: NSColor(white: 0, alpha: 0.05))
        case .contrast:
            Palette(background: .black, text: NSColor(srgbRed: 1, green: 0.93, blue: 0.2, alpha: 1), read: NSColor(white: 1, alpha: 0.4),
                    heading: NSColor(white: 1, alpha: 0.7), cue: NSColor(srgbRed: 0.35, green: 0.85, blue: 1, alpha: 1), band: NSColor(white: 1, alpha: 0.1))
        }
    }

    enum Font {
        static let caption = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let figure = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()
    }
}

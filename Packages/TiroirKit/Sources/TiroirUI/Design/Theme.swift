import SwiftUI
import TiroirCore

/// Tiroir's colors (spec 7), the same values as `brand/tokens/tokens.json`; `ThemeTests` keeps them in step.
public enum Theme {
    // MARK: Brand palette

    /// Warm black: windows and dark surfaces.
    public static let night = RGBA(hex: "#0C0B0A")!
    /// Raised dark surfaces.
    public static let lacquer = RGBA(hex: "#17150F")!
    /// Text on dark.
    public static let rice = RGBA(hex: "#F5F1EA")!
    /// Secondary text on dark.
    public static let ash = RGBA(hex: "#9D968B")!
    /// The accent on dark: a lamp in a drawer.
    public static let honey = RGBA(hex: "#FFB938")!
    /// The accent on light: links and buttons.
    public static let deepHoney = RGBA(hex: "#8F5600")!
    /// The second stop of the glow.
    public static let ember = RGBA(hex: "#FF8A1F")!
    /// Light page background.
    public static let paper = RGBA(hex: "#FAF8F4")!
    /// Text on light.
    public static let ink = RGBA(hex: "#1C1A17")!
    /// Secondary text on light.
    public static let graphite = RGBA(hex: "#6E6A63")!
    /// Separators on light, never text.
    public static let hairline = RGBA(hex: "#DAD5CC")!

    // MARK: Interface

    /// The dark windows: welcome and Settings.
    public static let window = Color(night)
    public static let sidebar = Color(lacquer)
    public static let text = Color(rice)
    public static let secondaryText = Color(rice).opacity(0.62)
    public static let tertiaryText = Color(rice).opacity(0.46)
    public static let accent = Color(honey)
    public static let accentDeep = Color(ember)
    public static let cardFill = Color.white.opacity(0.05)
    public static let cardStroke = Color.white.opacity(0.08)
    public static let hover = Color.white.opacity(0.08)
    public static let selection = Color(honey).opacity(0.22)
    public static let warning = Color(red: 1, green: 0.62, blue: 0.04)

    // MARK: Shape and space

    public static let smallRadius: CGFloat = 8
    public static let radius: CGFloat = 12
    public static let cardRadius: CGFloat = 16
    public static let panelRadius: CGFloat = 22
    /// Room around a glass panel inside its window, for the soft shadow SwiftUI draws: the window server's own shadow
    /// outlines a transparent window's rectangle on macOS 26.
    static let panelShadowRoom: CGFloat = 22
    public static let gutter: CGFloat = 20
}

extension Color {
    public init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

extension NSColor {
    public convenience init(_ rgba: RGBA) {
        self.init(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
}

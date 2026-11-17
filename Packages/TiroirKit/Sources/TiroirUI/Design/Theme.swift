import SwiftUI
import TiroirCore

/// The drawers' colors: Col's dark windows, and the Mac's own accent, chosen in System Settings, Appearance, as everywhere
/// in Col.
@available(macOS 26, *)
public enum Theme {
    // MARK: Palette

    /// The dark windows, the same black as Col's welcome.
    public static let night = RGBA(hex: "#0D0D0E")!
    /// Raised dark surfaces.
    public static let lacquer = RGBA(hex: "#1C1C1E")!
    /// Text on dark.
    public static let rice = RGBA(hex: "#F5F5F7")!
    /// Secondary text on dark.
    public static let ash = RGBA(hex: "#98989F")!

    // MARK: Interface

    /// The welcome and the drawers' settings.
    public static let window = Color(night)
    public static let sidebar = Color(lacquer)
    public static let text = Color(rice)
    public static let secondaryText = Color(rice).opacity(0.62)
    public static let tertiaryText = Color(rice).opacity(0.46)
    public static let accent = Color.accentColor
    public static let accentDeep = Color.accentColor.opacity(0.7)
    public static let cardFill = Color.white.opacity(0.05)
    public static let cardStroke = Color.white.opacity(0.08)
    public static let hover = Color.white.opacity(0.08)
    public static let selection = Color.accentColor.opacity(0.22)
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

@available(macOS 26, *)
extension Color {
    public init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

@available(macOS 26, *)
extension NSColor {
    public convenience init(_ rgba: RGBA) {
        self.init(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
}

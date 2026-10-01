import AppKit
import ColCore
import SwiftUI

/// Col's design tokens. The island is black; its accent is the Mac's own, the colour chosen in System Settings,
/// Appearance, as in Apple's apps (blue unless changed). Greys follow the system's label colours on dark, and radii are
/// concentric with the island's rounded corners.
enum Theme {
    /// The accent for SwiftUI: buttons, switches, selection, what is on.
    static var accent: Color { Color.accentColor }

    /// The same accent for drawings outside SwiftUI, as it shows on black, read when they are drawn.
    @MainActor static var accentRGBA: RGBA {
        var color = NSColor.systemBlue
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            color = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        }
        return RGBA(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
    }

    // The system's secondary and tertiary label colours on a dark background.
    static let secondaryText = Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.6)
    static let tertiaryText = Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.3)
    static let fill = Color.white.opacity(0.08)
    static let raisedFill = Color.white.opacity(0.14)

    /// The open island's lower corner radius (IslandLayout's expanded shape).
    static let islandCorner: CGFloat = 34
    /// Where the pages sit inside the open island.
    static let inset = EdgeInsets(top: 10, leading: 20, bottom: 18, trailing: 20)
    /// Cards that reach the bottom of a page share the island's curve: its radius minus the inset.
    static let cardRadius: CGFloat = islandCorner - inset.bottom
    /// Rows and chips inside cards.
    static let innerRadius: CGFloat = 10

    enum Font {
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let figure = SwiftUI.Font.system(size: 10.5, weight: .medium).monospacedDigit()
    }
}

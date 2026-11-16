import Foundation

/// Where the lyrics sit on the Lock Screen: below the clock and the date, above the user's picture, name and password
/// field, centred. Since macOS 14 the date and the clock end less than a third of the way down, and the user's area,
/// with Touch ID's prompt and the password field once a key is pressed, keeps to the lowest quarter: the band between
/// is free on every MacBook screen size.
public enum LockScreenLayout {
    /// Share of the screen's height, from its top edge, that the date and the clock take.
    public static let clockShare = 0.34
    /// Share of the screen's height, from its bottom edge, that the user's picture, name and password field take.
    public static let userShare = 0.27
    /// The clock and the user's area keep their size in points when a display mode makes the screen fewer points
    /// tall (Larger Text): never less room than this for each, whatever the share.
    public static let clockClearance = 250.0
    public static let userClearance = 250.0
    /// Space kept free above and below the card.
    public static let margin = 14.0

    /// The band between the clock and the user's area, in screen coordinates with the origin at the bottom left, as
    /// AppKit counts them.
    public static func band(screen: CGRect) -> CGRect {
        let top = screen.maxY - max(screen.height * clockShare, clockClearance)
        let bottom = screen.minY + max(screen.height * userShare, userClearance)
        return CGRect(x: screen.minX, y: bottom, width: screen.width, height: max(0, top - bottom))
    }

    /// The card of lyrics and controls: centred in the band, half the screen wide (between 480 and 720 points), as
    /// tall as the band allows up to 440 points. On the shortest screens it holds the controls and a line or two.
    public static func card(screen: CGRect) -> CGRect {
        let band = band(screen: screen)
        let width = min(max(screen.width * 0.5, 480), 720, max(0, screen.width - 2 * margin))
        let height = min(max(0, band.height - 2 * margin), 440)
        return CGRect(x: screen.midX - width / 2, y: band.midY - height / 2, width: width, height: height).integral
    }

    /// The card holds at least the controls: below this height, the Lock Screen shows its plain widgets instead.
    public static let smallestCard = 96.0
}

/// Where the lyrics show on the desktop.
public enum DesktopLyricsPosition: String, CaseIterable, Codable, Sendable {
    case center, lowerLeft, lowerCenter, lowerRight
}

/// How big the lyrics are on the desktop.
public enum DesktopLyricsSize: String, CaseIterable, Codable, Sendable {
    case small, medium, large

    /// The size of the line being sung, in points; the next line is half as big.
    public var lineSize: Double {
        switch self {
        case .small: 26
        case .medium: 38
        case .large: 54
        }
    }
}

public enum DesktopLyricsLayout {
    /// The window of the lyrics on a screen's visible frame (without the menu bar and the Dock), origin at the bottom
    /// left: room for three lines of the line being sung and two of the next, and for their shadow.
    public static func frame(position: DesktopLyricsPosition, size: DesktopLyricsSize, visible: CGRect) -> CGRect {
        let line = size.lineSize
        let height = min(line * 1.25 * 3 + line * 0.5 * 1.25 * 2 + line * 0.6, visible.height)
        let side = visible.width * 0.05
        let bottom = visible.minY + visible.height * 0.08
        let width: Double
        let x: Double
        switch position {
        case .center:
            width = visible.width * 0.72
            x = visible.midX - width / 2
        case .lowerCenter:
            width = visible.width * 0.62
            x = visible.midX - width / 2
        case .lowerLeft:
            width = visible.width * 0.44
            x = visible.minX + side
        case .lowerRight:
            width = visible.width * 0.44
            x = visible.maxX - side - width
        }
        let y = position == .center ? visible.midY - height / 2 : bottom
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}

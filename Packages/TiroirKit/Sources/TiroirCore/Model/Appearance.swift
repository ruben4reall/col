import Foundation

/// A color in sRGB, stored as components between 0 and 1.
public struct RGBA: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#FFB938" or "FFB938", with an optional alpha pair ("#FFB93880").
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        red = Double((value >> (16 + shift)) & 0xFF) / 255
        green = Double((value >> (8 + shift)) & 0xFF) / 255
        blue = Double((value >> shift) & 0xFF) / 255
        alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
    }

    public var hex: String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    public var clamped: RGBA {
        RGBA(red: red.clamped(to: 0...1), green: green.clamped(to: 0...1), blue: blue.clamped(to: 0...1), alpha: alpha.clamped(to: 0...1))
    }

    /// Relative luminance (WCAG 2), for contrast checks.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two opaque colors, from 1 to 21.
    public func contrast(with other: RGBA) -> Double {
        let (light, dark) = luminance > other.luminance ? (luminance, other.luminance) : (other.luminance, luminance)
        return (light + 0.05) / (dark + 0.05)
    }
}

/// How Tiroir dresses the menu bar (spec 6.3, Appearance): a shape, and a look drawn in it, with a second look for
/// Dark Mode when the person wants one.
public struct Appearance: Codable, Hashable, Sendable {
    public enum Tint: String, Codable, Sendable, CaseIterable {
        case none, color, gradient
    }

    /// The outline of what Tiroir draws over the menu bar, the same in Light and Dark Mode.
    public enum Shape: String, Codable, Sendable, CaseIterable {
        /// Edge to edge, like the menu bar itself.
        case full
        /// One rounded bar, inset from the screen's edges.
        case floating
        /// Two rounded pieces, one behind the app menus and one behind the icons, with the desktop between them.
        case split
    }

    /// What the menu bar shows in one of the system's appearances: its tint, hairline and shadow.
    public struct Look: Codable, Hashable, Sendable {
        public var tint: Tint
        public var color: RGBA
        /// The right end of a gradient, which starts from `color` on the left.
        public var gradientEnd: RGBA
        /// How strongly the tint shows, from 0 to 1.
        public var opacity: Double
        /// A hairline along the edge of what is drawn.
        public var border: Bool
        /// A soft shadow under what is drawn.
        public var shadow: Bool

        public init(
            tint: Tint = .none, color: RGBA = RGBA(hex: "#FFB938")!, gradientEnd: RGBA = RGBA(hex: "#FF8A1F")!,
            opacity: Double = 0.35, border: Bool = false, shadow: Bool = false
        ) {
            self.tint = tint
            self.color = color
            self.gradientEnd = gradientEnd
            self.opacity = opacity
            self.border = border
            self.shadow = shadow
        }

        public static let standard = Look()

        /// Whether this look draws anything at all.
        public var isVisible: Bool { tint != .none || border || shadow }

        public var clamped: Look {
            var copy = self
            copy.color = color.clamped
            copy.gradientEnd = gradientEnd.clamped
            copy.opacity = opacity.clamped(to: 0...1)
            return copy
        }

        private enum CodingKeys: String, CodingKey { case tint, color, gradientEnd, opacity, border, shadow }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let standard = Look()
            tint = (try? container.decodeIfPresent(Tint.self, forKey: .tint)) ?? standard.tint
            color = (try? container.decodeIfPresent(RGBA.self, forKey: .color)) ?? standard.color
            gradientEnd = (try? container.decodeIfPresent(RGBA.self, forKey: .gradientEnd)) ?? standard.gradientEnd
            opacity = (try? container.decodeIfPresent(Double.self, forKey: .opacity)) ?? standard.opacity
            border = (try? container.decodeIfPresent(Bool.self, forKey: .border)) ?? standard.border
            shadow = (try? container.decodeIfPresent(Bool.self, forKey: .shadow)) ?? standard.shadow
        }
    }

    // The main look, kept in flat fields as Tiroir 1.0 saved it; `look` gathers them.
    public var tint: Tint
    public var color: RGBA
    /// The right end of a gradient, which starts from `color` on the left.
    public var gradientEnd: RGBA
    /// How strongly the tint shows, from 0 to 1.
    public var opacity: Double
    /// A hairline along the edge of what is drawn.
    public var border: Bool
    /// A soft shadow under what is drawn.
    public var shadow: Bool
    public var shape: Shape
    /// The look while the Mac is in Dark Mode; nil when the main look serves in both.
    public var darkLook: Look?

    public init(
        tint: Tint = .none, color: RGBA = Look.standard.color, gradientEnd: RGBA = Look.standard.gradientEnd,
        opacity: Double = Look.standard.opacity, border: Bool = false, shadow: Bool = false, shape: Shape = .full,
        darkLook: Look? = nil
    ) {
        self.tint = tint
        self.color = color
        self.gradientEnd = gradientEnd
        self.opacity = opacity
        self.border = border
        self.shadow = shadow
        self.shape = shape
        self.darkLook = darkLook
    }

    public static let standard = Appearance()

    /// The main look: the one shown in Light Mode, and in Dark Mode too without a dark look.
    public var look: Look {
        get { Look(tint: tint, color: color, gradientEnd: gradientEnd, opacity: opacity, border: border, shadow: shadow) }
        set {
            tint = newValue.tint
            color = newValue.color
            gradientEnd = newValue.gradientEnd
            opacity = newValue.opacity
            border = newValue.border
            shadow = newValue.shadow
        }
    }

    /// The look to show while the Mac is in Dark Mode or not.
    public func look(inDarkMode isDark: Bool) -> Look {
        isDark ? darkLook ?? look : look
    }

    /// Whether anything is drawn over the menu bar, in either mode.
    public var isVisible: Bool { look.isVisible || darkLook?.isVisible == true }

    public var clamped: Appearance {
        var copy = self
        copy.look = look.clamped
        copy.darkLook = darkLook?.clamped
        return copy
    }

    private enum CodingKeys: String, CodingKey { case tint, color, gradientEnd, opacity, border, shadow, shape, darkLook }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Tiroir 1.0 saved the main look in flat fields, and neither a shape nor a dark look: such settings read as
        // they were, edge to edge and the same in both modes.
        look = try Look(from: decoder)
        shape = (try? container.decodeIfPresent(Shape.self, forKey: .shape)) ?? Self.standard.shape
        darkLook = try? container.decodeIfPresent(Look.self, forKey: .darkLook)
    }
}

extension Comparable {
    /// The value, brought inside `range`.
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

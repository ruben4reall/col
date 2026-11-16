import CoreGraphics

public enum IslandState: Sendable, Equatable {
    /// Hidden inside the notch.
    case collapsed
    /// The pointer rests on the notch: the island swells slightly to say it is there.
    case peek
    /// Open, showing its content.
    case expanded
}

/// The island's outline: a body hanging from the top edge of the screen, with concave ears where it meets the menu
/// bar and rounded lower corners.
public struct IslandShape: Equatable, Sendable {
    /// Width of the body, ears excluded.
    public var width: CGFloat
    public var height: CGFloat
    /// Radius of the concave fillets joining the body to the top edge.
    public var earRadius: CGFloat
    /// Radius of the two lower corners.
    public var cornerRadius: CGFloat
    /// Distance below the top of the screen. Zero hangs the island from the top edge; more makes it float, rounded
    /// on all four corners, for screens without a notch.
    public var gap: CGFloat
    /// Horizontal shift of the body from the centre of the notch: a wing on one side only pulls it that way.
    public var offset: CGFloat

    public init(width: CGFloat, height: CGFloat, earRadius: CGFloat, cornerRadius: CGFloat, gap: CGFloat = 0, offset: CGFloat = 0) {
        self.width = width
        self.height = height
        self.earRadius = earRadius
        self.cornerRadius = cornerRadius
        self.gap = gap
        self.offset = offset
    }

    public var isFloating: Bool { gap > 0 }

    /// Width including both ears.
    public var outerWidth: CGFloat { isFloating ? width : width + earRadius * 2 }
}

/// How far the compact island reaches on each side of the camera. Both sides match unless the menu bar leaves room on
/// one side only: then the activity keeps a single wing instead of disappearing.
public struct Wings: Equatable, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public var leading: CGFloat
    public var trailing: CGFloat

    public init(leading: CGFloat, trailing: CGFloat) {
        self.leading = leading
        self.trailing = trailing
    }

    public init(_ both: CGFloat) { self.init(leading: both, trailing: both) }
    public init(floatLiteral value: Double) { self.init(CGFloat(value)) }
    public init(integerLiteral value: Int) { self.init(CGFloat(value)) }

    public static let none = Wings(0)

    public var isEmpty: Bool { leading <= 0 && trailing <= 0 }
    /// Only one side has a wing.
    public var isOneSided: Bool { (leading > 0) != (trailing > 0) }

    /// Each side kept between zero and the widest a wing may grow.
    func clamped(to maximum: CGFloat) -> Wings {
        Wings(leading: min(max(leading, 0), maximum), trailing: min(max(trailing, 0), maximum))
    }
}

/// How big the open island is. Standard matches the proportions of the iPhone's expanded island scaled to a Mac.
public enum IslandSize: String, CaseIterable, Sendable, Codable {
    case compact, standard, large

    /// Width of the open island and height of its content below the camera, in points.
    public var open: (width: CGFloat, content: CGFloat) {
        switch self {
        case .compact: (440, 140)
        case .standard: (480, 152)
        case .large: (540, 172)
        }
    }
}

/// How the island sits on a screen without a notch, where Col draws all of it.
public enum FloatingStyle: String, CaseIterable, Sendable, Codable {
    /// A small capsule inside the menu bar, clear of the top edge, the way the iPhone's island sits in its status bar.
    case pill
    /// A notch drawn by Col, hanging from the top edge like the camera housing of a MacBook.
    case notch
    /// A larger capsule below the menu bar.
    case below
}

/// Every size the island takes on one screen. The canvas is the largest area it ever covers, open, with room for
/// its shadow; the window only grows to it while the island is open.
public struct IslandLayout: Equatable, Sendable {
    public let notch: NotchMetrics

    public let size: IslandSize
    /// How the island looks where there is no notch. Under a real one, only `.below` changes anything: the island
    /// then floats below the menu bar instead of hanging from the notch.
    public let floating: FloatingStyle
    /// Free room beside the resting island on its tighter side, up to the nearest menu or icon, margin taken; nil when
    /// unknown. The swell under the pointer stays inside it.
    public var sideRoom: CGFloat?
    /// Widest a wing of the compact island may ever grow, whatever the setting: the canvas makes room for it.
    public static let maximumWing: CGFloat = 160
    /// Widest a wing grows by default, so a long title never swallows the menu bar.
    public static let standardWing: CGFloat = 132
    /// Widest a wing may grow on this screen, as the user chose (Settings, Appearance), up to `maximumWing`.
    public let wingLimit: CGFloat
    static let shadowMargin: CGFloat = 40

    /// Without a style, a real notch is hung from and a screen without one gets the capsule below its menu bar.
    public init(notch: NotchMetrics, size: IslandSize = .standard, floating: FloatingStyle? = nil, sideRoom: CGFloat? = nil,
                wingLimit: CGFloat = IslandLayout.standardWing) {
        self.notch = notch
        self.wingLimit = min(max(wingLimit, WingBudget.minimum), Self.maximumWing)
        self.size = size
        self.floating = floating ?? (notch.isHardware ? .notch : .below)
        self.sideRoom = sideRoom
    }

    /// The style in effect, nil for an island hanging from a real notch.
    public var style: FloatingStyle? {
        if notch.isHardware { return floating == .below ? .below : nil }
        return floating
    }

    /// The island sits in the menu bar row, where menus and icons around it must stay clear: under a real notch, as a
    /// drawn notch, or as a pill.
    public var sharesMenuBar: Bool { style != .below }

    /// How far the island reaches past its wings on each side, at most: its ears, and its swell under the pointer.
    /// Wings leave this much of their room free.
    public var wingOverhang: CGFloat {
        style == .pill ? Self.peekSwellWithWings / 2 : Self.wingEar + Self.peekSwellWithWings / 2
    }

    /// Radius of the ears of the island with an activity, and of the bare island under the pointer.
    static let wingEar: CGFloat = 5
    static let ear: CGFloat = 6
    /// How much wider the island grows under the pointer. With an activity its wings already fill the room they were
    /// given, so it only grows taller; bare, it also grows wider.
    static let peekSwellWithWings: CGFloat = 0
    static let peekSwell: CGFloat = 18

    /// The outline for a state. `wings` widens the island on both sides of the camera to show a live activity.
    public func shape(for state: IslandState, wings: Wings = .none) -> IslandShape {
        var shape = attachedShape(for: state, wings: wings)
        switch style {
        case nil, .notch?:
            return shape
        case .below?:
            // Below the menu bar the island floats, a capsule when closed.
            shape.gap = notch.height + Self.floatingGap
            shape.earRadius = 0
            if state != .expanded {
                shape.height = Self.floatingHeight + (state == .peek ? 4 : 0)
                shape.cornerRadius = shape.height / 2
            }
        case .pill?:
            // In the menu bar, clear of the top edge: a capsule closed, a card with four round corners open.
            shape.earRadius = 0
            shape.gap = pillInset
            switch state {
            case .collapsed:
                shape.height = pillHeight
            case .peek:
                shape.height = pillHeight + 2
                shape.gap = pillInset - 1
            case .expanded:
                shape.cornerRadius = 30
            }
            if state != .expanded { shape.cornerRadius = shape.height / 2 }
        }
        return shape
    }

    /// Height of the floating capsule, and its distance below the menu bar.
    static let floatingHeight: CGFloat = 34
    static let floatingGap: CGFloat = 6

    /// Distance between the pill and the top edge, and its height: centred in the menu bar.
    var pillInset: CGFloat { max(2, min(3, (notch.height - 16) / 2)) }
    var pillHeight: CGFloat { notch.height - pillInset * 2 }

    private func attachedShape(for state: IslandState, wings: Wings) -> IslandShape {
        let wings = wings.clamped(to: wingLimit)
        let span = wings.leading + wings.trailing
        let offset = (wings.trailing - wings.leading) / 2
        switch state {
        case .collapsed:
            return IslandShape(
                width: notch.width + span,
                height: notch.height,
                earRadius: wings.isEmpty ? 4 : Self.wingEar,
                cornerRadius: wings.isEmpty ? 9 : 12,
                offset: offset
            )
        case .peek:
            return IslandShape(
                width: notch.width + span + peekSwell(wings), height: notch.height + 5,
                earRadius: wings.isEmpty ? Self.ear : Self.wingEar, cornerRadius: 13, offset: offset
            )
        case .expanded:
            return IslandShape(
                width: max(size.open.width, notch.width + 160),
                height: notch.height + size.open.content,
                earRadius: 14,
                cornerRadius: 34
            )
        }
    }

    /// How much wider the island grows under the pointer. Bare, it swells as far as the menu bar lets it, and only
    /// grows taller when a menu sits right against it.
    private func peekSwell(_ wings: Wings) -> CGFloat {
        guard wings.isEmpty else { return Self.peekSwellWithWings }
        guard let sideRoom else { return Self.peekSwell }
        let ear = style == .pill ? 0 : Self.ear
        return min(Self.peekSwell, max(0, (sideRoom - ear) * 2)).rounded(.down)
    }

    /// Size of the window for a state. Collapsed and peeking, it hugs the shape so the menu bar around the notch
    /// keeps receiving clicks; open, it leaves room for the shadow.
    /// The window stays centred on the notch, so a shape pulled to one side widens it on both.
    public func windowSize(for state: IslandState, wings: Wings = .none) -> CGSize {
        let shape = shape(for: state, wings: wings)
        guard state == .expanded else {
            return CGSize(width: shape.outerWidth + abs(shape.offset) * 2, height: shape.gap + shape.height)
        }
        return CGSize(width: shape.outerWidth + Self.shadowMargin * 2, height: shape.gap + shape.height + Self.shadowMargin)
    }

    public var canvasSize: CGSize {
        let open = windowSize(for: .expanded)
        let widest = notch.width + Self.maximumWing * 2 + Self.peekSwell + Self.ear * 2
        return CGSize(width: max(open.width, widest), height: open.height)
    }

    /// Where a wing's item sits, centred in the wing beside the camera, top-left origin.
    public func wingCenter(leading: Bool, wings: Wings) -> CGPoint {
        let wings = wings.clamped(to: wingLimit)
        let offset = notch.width / 2 + (leading ? wings.leading : wings.trailing) / 2
        let collapsed = shape(for: .collapsed, wings: wings)
        return CGPoint(x: canvasSize.width / 2 + (leading ? -offset : offset), y: collapsed.gap + collapsed.height / 2)
    }

    /// The open island's body in the canvas, top-left origin: the content lays itself out in it, leaving the camera
    /// alone in the top row.
    public var contentFrame: CGRect {
        let open = shape(for: .expanded)
        return CGRect(x: (canvasSize.width - open.width) / 2, y: open.gap, width: open.width, height: open.height)
    }

    /// Bounding box of the shape for a state in the canvas, top-left origin.
    public func frame(for state: IslandState, wings: Wings = .none) -> CGRect {
        let shape = shape(for: state, wings: wings)
        return CGRect(x: (canvasSize.width - shape.outerWidth) / 2 + shape.offset, y: shape.gap, width: shape.outerWidth, height: shape.height)
    }
}

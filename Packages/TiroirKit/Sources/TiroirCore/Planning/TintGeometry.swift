import CoreGraphics
import Foundation

/// Where the tint goes on one display (spec 6.3, Appearance): the pieces each shape fills, worked out from the screen
/// and from what Tiroir could measure of the menu bar.
///
/// The split shape needs to know where its two pieces end. Beside a notch they end at the notch; elsewhere the left
/// piece ends after the front app's menus and the right one starts before the leftmost icon. When one of those
/// measures is missing, the bar floats instead: Tiroir never guesses where the menus or the icons are.
public enum TintGeometry {
    /// What to fill on one display.
    public struct Pieces: Equatable, Sendable {
        /// From left to right: the whole menu bar, one bar, or two pieces. Empty while the menu bar hides itself.
        public var rects: [CGRect]
        /// Half the height of a rounded piece, so its ends are round; zero edge to edge.
        public var radius: CGFloat
        /// The shape drawn, which is not always the one asked for: split floats when a measure is missing, and a
        /// screen too small for rounded pieces is tinted edge to edge.
        public var shape: Appearance.Shape

        public init(rects: [CGRect], radius: CGFloat, shape: Appearance.Shape) {
            self.rects = rects
            self.radius = radius
            self.shape = shape
        }
    }

    /// The room between a rounded piece and the screen's edge, the notch, the app menus or the icons.
    public static let sideInset: CGFloat = 6
    /// The room above and below a rounded piece.
    public static let verticalInset: CGFloat = 3

    /// The pieces of `shape` on one screen.
    ///
    /// - Parameters:
    ///   - screen: the screen's frame, in AppKit's coordinates: the menu bar runs along its top edge.
    ///   - menuBarHeight: the menu bar's height, zero while it hides itself.
    ///   - notchLeft: the screen's `auxiliaryTopLeftArea`, left of the camera housing. Only its width counts, which is
    ///     the same in any coordinates.
    ///   - notchRight: the screen's `auxiliaryTopRightArea`, right of the camera housing.
    ///   - menusEnd: where the front app's menus end on this screen, when Tiroir could measure it.
    ///   - statusStart: where the leftmost icon starts on this screen, when Tiroir could measure it.
    public static func pieces(
        for shape: Appearance.Shape, screen: CGRect, menuBarHeight: CGFloat, notchLeft: CGRect? = nil,
        notchRight: CGRect? = nil, menusEnd: CGFloat? = nil, statusStart: CGFloat? = nil
    ) -> Pieces {
        let height = min(max(menuBarHeight, 0), screen.height)
        guard height > 0, screen.width > 0 else { return Pieces(rects: [], radius: 0, shape: shape) }
        let bar = CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
        let edgeToEdge = Pieces(rects: [bar], radius: 0, shape: .full)
        let pieceHeight = height - 2 * verticalInset

        // A rounded piece between two points of the bar, or nil when it would be no longer than it is tall: a dot.
        func piece(from left: CGFloat, to right: CGFloat) -> CGRect? {
            guard pieceHeight > 0, right - left >= pieceHeight else { return nil }
            return CGRect(x: left, y: bar.minY + verticalInset, width: right - left, height: pieceHeight)
        }

        guard shape != .full, let whole = piece(from: bar.minX + sideInset, to: bar.maxX - sideInset) else {
            return edgeToEdge
        }
        let floating = Pieces(rects: [whole], radius: pieceHeight / 2, shape: .floating)
        guard shape == .split else { return floating }

        let leftEnd, rightStart: CGFloat
        if let notchLeft, let notchRight {
            leftEnd = bar.minX + notchLeft.width - sideInset
            rightStart = bar.maxX - notchRight.width + sideInset
        } else if let menusEnd, let statusStart {
            leftEnd = menusEnd + sideInset
            rightStart = statusStart - sideInset
        } else {
            return floating
        }
        // The desktop shows between the pieces, at least as wide as they are tall: a narrower gap reads as a flaw.
        guard rightStart - leftEnd >= pieceHeight,
              let left = piece(from: whole.minX, to: leftEnd),
              let right = piece(from: rightStart, to: whole.maxX) else { return floating }
        return Pieces(rects: [left, right], radius: pieceHeight / 2, shape: .split)
    }

    /// Where the app menus end in one menu bar: the right edge of the last menu whose middle lies in it, nil without
    /// one. `menus` and `menuBar` share their coordinates.
    public static func menusEnd(of menus: [CGRect], in menuBar: CGRect) -> CGFloat? {
        menus.filter { menuBar.contains(CGPoint(x: $0.midX, y: $0.midY)) }.map(\.maxX).max()
    }

    /// Where the icons start in one menu bar: the left edge of the leftmost icon whose middle lies in it, nil without
    /// one. `icons` and `menuBar` share their coordinates.
    public static func statusStart(of icons: [CGRect], in menuBar: CGRect) -> CGFloat? {
        icons.filter { menuBar.contains(CGPoint(x: $0.midX, y: $0.midY)) }.map(\.minX).min()
    }
}

import CoreGraphics
import Foundation

/// How much of the menu bar's room the visible icons take (spec 6.4, Notch).
///
/// On a MacBook with a notch, icons can only sit between the notch and the right edge; whatever does not fit, macOS
/// hides without a word on macOS 26 and folds behind « on 27. Tiroir's own drawers count too: a drawer lost behind the
/// notch would lock its icons away.
public enum NotchCapacity {
    public struct Item: Equatable, Sendable {
        public var id: IconID
        public var width: CGFloat
        public init(id: IconID, width: CGFloat) {
            self.id = id
            self.width = width
        }
    }

    public struct Result: Equatable, Sendable {
        /// Points available for icons.
        public var room: CGFloat
        /// Points the icons need.
        public var used: CGFloat
        /// The icons that do not fit, from the left.
        public var overflow: [IconID]

        public var fits: Bool { overflow.isEmpty }
        /// Used room as a share of the room, for a gauge; above 1 when icons overflow.
        public var share: Double { room > 0 ? Double(used / room) : (used > 0 ? 2 : 0) }
    }

    /// - Parameters:
    ///   - room: the width available for icons, from the notch (or the end of the app menus) to the right edge.
    ///   - items: every icon that shows, Tiroir's drawers included, from right to left.
    ///   - spacing: the gap macOS leaves between two icons, when widths do not include it.
    public static func evaluate(room: CGFloat, items: [Item], spacing: CGFloat = 0) -> Result {
        var used: CGFloat = 0
        var overflow: [IconID] = []
        for (index, item) in items.enumerated() {
            let needed = item.width + (index > 0 ? spacing : 0)
            if used + needed > room + 0.5 { overflow.append(item.id) }
            used += needed
        }
        return Result(room: room, used: used, overflow: overflow.reversed())
    }
}

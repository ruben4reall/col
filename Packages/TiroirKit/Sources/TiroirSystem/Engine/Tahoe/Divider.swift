import AppKit

/// Tiroir's divider on macOS 26: an invisible status item. Icons on its left are out of the menu bar while it is
/// expanded, because it grows wide enough to push them past the left edge of the screen. The technique comes from
/// Hidden Bar (MIT), rewritten.
@MainActor
public protocol DividerControlling: AnyObject {
    /// The divider in window server coordinates, nil before macOS has placed it.
    var frame: CGRect? { get }
    var isExpanded: Bool { get }
    func expand()
    func relax()
    /// Keeps the divider's place for the next launch.
    func rememberPlace()
    func remove()
}

@MainActor
public final class Divider: DividerControlling {
    public static let autosaveName = "tiroir.divider"
    /// Relaxed, the divider keeps one point: macOS 26 may never give a zero-length item a window.
    static let relaxedLength: CGFloat = 1
    static let savedPositionKey = "tiroir.divider.position"
    /// macOS orders items by this distance from the right end: Tiroir's icon has 0 and its drawers 1 and up; every
    /// other item remembers more.
    static let firstPlace: Double = 60

    private var item: NSStatusItem?
    public private(set) var isExpanded = false

    static let preferredPositionKey = "NSStatusItem Preferred Position \(autosaveName)"

    public init() {
        let defaults = UserDefaults.standard
        // macOS writes an item's place each time it is dragged, and forgets it when the item is removed. Tiroir keeps a
        // copy after each arrangement and at quit, and puts it back, so the divider comes back between the same icons
        // at the next launch; after a crash, macOS's own value is still there, and newer. Without either, just left of
        // Tiroir's own items: every other icon starts on the concealed side (nothing disappears while the divider stays
        // narrow), and the first arrangement drags the divider once to its place. Far left, on a crowded menu bar, the
        // divider would sit under the notch, where no drop lands.
        if defaults.object(forKey: Self.preferredPositionKey) == nil {
            let saved = defaults.object(forKey: Self.savedPositionKey) as? Double
            defaults.set(saved ?? Self.firstPlace, forKey: Self.preferredPositionKey)
        }
        defaults.set(true, forKey: "NSStatusItem Visible \(Self.autosaveName)")
        defaults.set(true, forKey: "NSStatusItem VisibleCC \(Self.autosaveName)")

        let item = NSStatusBar.system.statusItem(withLength: Self.relaxedLength)
        item.autosaveName = Self.autosaveName
        item.behavior = []
        if let button = item.button {
            button.image = nil
            button.title = ""
            button.setAccessibilityElement(false)
            button.appearsDisabled = true
        }
        self.item = item
    }

    public var frame: CGRect? {
        guard let window = item?.button?.window else { return nil }
        return ScreenCoordinates.windowServerRect(fromAppKit: window.frame)
    }

    /// Wide enough to push every icon on its left past the screen's left edge: twice the widest display, at least
    /// 500 points, at most the 10 000 points macOS allows.
    static var expandedLength: CGFloat {
        let widest = NSScreen.screens.map(\.frame.width).max() ?? 2000
        return min(max(500, widest * 2), 10_000)
    }

    public func expand() {
        guard let item, !isExpanded else { return }
        item.length = Self.expandedLength
        isExpanded = true
        Log.engine.notice("divider widened to \(Int(item.length))")
    }

    public func relax() {
        guard let item else { return }
        if item.length != Self.relaxedLength {
            item.length = Self.relaxedLength
            Log.engine.notice("divider narrowed")
        }
        isExpanded = false
    }

    /// A middle width while Tiroir arranges icons: wide enough for a drop to land on either side of the divider, and
    /// every icon stays on screen.
    public func setArranging() {
        guard let item else { return }
        item.length = TahoeEngine.arrangingLength
        isExpanded = false
    }

    public func rememberPlace() {
        let defaults = UserDefaults.standard
        if let position = defaults.object(forKey: Self.preferredPositionKey) as? Double {
            defaults.set(position, forKey: Self.savedPositionKey)
        }
    }

    /// Keeps the divider's place for the next launch, then takes it out of the menu bar: every icon comes back.
    public func remove() {
        guard let item else { return }
        rememberPlace()
        item.length = Self.relaxedLength
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        isExpanded = false
    }
}

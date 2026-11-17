import AppKit
import CoreGraphics

/// One window of the menu bar's icons, as the window server lists it (macOS 26).
public struct StatusWindow: Equatable, Sendable {
    public var id: UInt32
    /// Top-left origin, main display.
    public var frame: CGRect
    public var ownerPID: pid_t

    public init(id: UInt32, frame: CGRect, ownerPID: pid_t) {
        self.id = id
        self.frame = frame
        self.ownerPID = ownerPID
    }
}

/// Where the engine reads windows. The system implementation reads the window server; tests use a simulated bar.
public protocol StatusWindowSource: Sendable {
    /// Every icon window (status window level), from right to left, including the ones pushed off screen.
    func statusWindows() -> [StatusWindow]
    /// Windows of these apps on screen above ordinary windows (menus, popovers, panels, overlays), the menu bar's own
    /// windows left out, by number. What pressing an icon opened is what appears here after the press.
    func raisedWindows(ownerPIDs: Set<pid_t>) -> Set<UInt32>
}

/// The window server, through the public window list. Needs no permission: only window names would need Screen
/// Recording, and Tiroir never reads them.
public struct SystemStatusWindows: StatusWindowSource {
    public init() {}

    static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    static let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    static let popUpMenuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

    public func statusWindows() -> [StatusWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info -> StatusWindow? in
            guard info[kCGWindowLayer as String] as? Int == Self.statusLevel,
                  let number = info[kCGWindowNumber as String] as? Int, let id = UInt32(exactly: number),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  let owner = info[kCGWindowOwnerPID as String] as? Int else { return nil }
            return StatusWindow(id: id, frame: frame, ownerPID: pid_t(owner))
        }
        .sorted { $0.frame.midX > $1.frame.midX }
    }

    public func raisedWindows(ownerPIDs: Set<pid_t>) -> Set<UInt32> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        var result = Set<UInt32>()
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer > 0,
                  let owner = info[kCGWindowOwnerPID as String] as? Int, ownerPIDs.contains(pid_t(owner)),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let number = info[kCGWindowNumber as String] as? Int, let id = UInt32(exactly: number),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
            // The bar and its icons are no menu.
            if [Self.statusLevel, Self.mainMenuLevel].contains(layer), frame.height <= 40 { continue }
            result.insert(id)
        }
        return result
    }

    /// Whether any app has a menu, a popover or a panel open from the menu bar.
    public static func anyMenuIsOpen() -> Bool {
        !openMenuFrames(ownerPIDs: nil).isEmpty
    }

    /// Frames of the menus and popovers on screen whose window belongs to one of `ownerPIDs`, or to anyone for nil.
    static func openMenuFrames(ownerPIDs: Set<pid_t>?) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let displays = displayBounds()
        return list.compactMap { info -> CGRect? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let owner = info[kCGWindowOwnerPID as String] as? Int, ownerPIDs?.contains(pid_t(owner)) ?? true,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return isMenu(layer: layer, frame: frame, displays: displays) ? frame : nil
        }
    }

    /// Menus live at the pop-up menu level; popovers and panels that icons open sit at or near the menu bar's levels
    /// and are taller than the bar itself. No menu covers a whole display: a window that does is an overlay (the
    /// screenshot tool keeps one at the menu bar's level), never a menu someone is reading.
    nonisolated static func isMenu(layer: Int, frame: CGRect, displays: [CGRect]) -> Bool {
        let isMenu = layer == popUpMenuLevel || layer == popUpMenuLevel - 1
        let isPanel = [mainMenuLevel, statusLevel].contains(layer) && frame.height > 40
        let coversADisplay = displays.contains { frame.insetBy(dx: -2, dy: -2).contains($0) }
        return (isMenu || isPanel) && !coversADisplay
    }

    /// Every active display, in window server coordinates.
    static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
}

/// Converts between AppKit's screen coordinates (bottom-left origin) and the window server's (top-left origin of the
/// main display).
public enum ScreenCoordinates {
    @MainActor
    public static var mainDisplayHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    @MainActor
    public static func windowServerRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor
    public static func appKitRect(fromWindowServer rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Whether a window server rectangle lies on any display.
    @MainActor
    public static func isOnScreen(_ rect: CGRect) -> Bool {
        let height = mainDisplayHeight
        return NSScreen.screens.contains { screen in
            let frame = screen.frame
            let flipped = CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
            return flipped.intersection(rect).width >= rect.width * 0.5
        }
    }
}

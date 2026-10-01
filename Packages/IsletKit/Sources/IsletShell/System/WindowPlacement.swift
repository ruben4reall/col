import AppKit
import IsletCore

/// Where windows that open from the island go: the island's screen, the bottom of the open island and the middle of
/// the notch, in screen coordinates.
struct WindowAnchor {
    let screen: NSScreen
    let islandBottom: CGFloat
    let centerX: CGFloat

    /// Without a running island: the main screen, as if an island of standard size hung from its top.
    @MainActor static var main: WindowAnchor? {
        guard let screen = NSScreen.main else { return nil }
        let open = IslandSize.standard.open
        return WindowAnchor(screen: screen, islandBottom: screen.frame.maxY - 32 - open.content, centerX: screen.frame.midX)
    }
}

/// Where Islet's windows open: below the open island with some air, centred on the notch, on the island's screen,
/// never under the island.
@MainActor
enum WindowPlacement {
    /// Air between the bottom of the open island and the top of a window.
    static let gapBelowIsland: CGFloat = 24

    /// Places a window at the size it had last time (kept under `sizeKey`), shortened if the screen has no room for it.
    static func belowIsland(_ window: NSWindow, preferred: NSSize, minimum: NSSize, sizeKey: String, forcedHeight: CGFloat? = nil) {
        guard let anchor = IslandController.shared?.windowAnchor ?? WindowAnchor.main else {
            window.center()
            return
        }
        let visible = anchor.screen.visibleFrame
        var size = UserDefaults.standard.string(forKey: sizeKey).map(NSSizeFromString) ?? preferred
        if size.width < minimum.width || size.height < minimum.height { size = preferred }
        if let forcedHeight { size.height = forcedHeight }
        let top = min(visible.maxY, anchor.islandBottom - gapBelowIsland)
        size.height = max(min(size.height, top - visible.minY - 16), min(minimum.height, visible.height - 16))
        size.width = min(size.width, visible.width - 32)
        let x = min(max(anchor.centerX - size.width / 2, visible.minX + 16), visible.maxX - size.width - 16)
        let y = max(top - size.height, visible.minY + 8)
        window.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: false)
    }
}

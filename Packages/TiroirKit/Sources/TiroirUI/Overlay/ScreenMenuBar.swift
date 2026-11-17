import AppKit

extension NSScreen {
    /// The display's identifier, which outlives a rearrangement of the displays.
    public var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The strip between the top of the visible frame and the top of the screen; empty when the menu bar hides itself.
    public var menuBarFrame: CGRect {
        CGRect(x: frame.minX, y: visibleFrame.maxY, width: frame.width, height: max(0, frame.maxY - visibleFrame.maxY))
    }

    /// Whether the screen has a camera housing in its menu bar: macOS then describes the room on each side of it.
    public var hasNotch: Bool {
        auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil
    }
}

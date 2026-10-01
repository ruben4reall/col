import AppKit

/// A borderless panel above the menu bar that never takes focus from the app the user is working in.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Above the menu bar, on every Space, and over full screen apps.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// True while a field of the island takes the keyboard, such as the question to an AI. The panel then becomes key
    /// without activating Islet, as Spotlight does, and gives the keyboard back when the island closes.
    var acceptsKeyboard = false

    override var canBecomeKey: Bool { acceptsKeyboard }

    /// Called whenever the panel stops being key: Escape, the island closing, or a click in another app.
    var onResignKey: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
    override var canBecomeMain: Bool { false }

    /// AppKit pushes windows below the menu bar; the island lives in it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

import AppKit

/// A borderless panel above everything that never takes focus from the app the reader is in, unless it covers a
/// whole screen, where it takes the keyboard (Space, arrows, Escape).
final class PrompterPanel: NSPanel {
    var takesKeyboard = false
    var onKey: ((NSEvent) -> Bool)?

    init(movable: Bool) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = movable
        isMovableByWindowBackground = movable
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Above the menu bar and other notch apps, on every Space, and over full screen apps.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { takesKeyboard }
    override var canBecomeMain: Bool { false }

    /// AppKit pushes windows below the menu bar; the notch prompter lives in it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

/// A view backed directly by a shape layer.
final class ShapeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { CAShapeLayer() }

    // swiftlint:disable:next force_cast
    var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The three places the prompter can live share this interface.
@MainActor
protocol PrompterPresentation: AnyObject {
    var text: ScriptTextView { get }
    /// Shows the prompter, opening with its motion.
    func present()
    /// Closes with its motion, then removes the window.
    func dismiss(completion: @escaping @MainActor () -> Void)
    /// Removes the window at once, when another take replaces this one.
    func closeNow()
    /// Re-reads the settings that change the window (size, capture, screen).
    func refresh()
    /// The stage light around the prompter, from 0 (off) to 1.
    func glow(_ intensity: CGFloat)
}

enum Screens {
    /// The screen with the notch, else the built-in one, else the main one.
    @MainActor static var notch: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first { CGDisplayIsBuiltin(displayID($0)) != 0 }
            ?? NSScreen.main
    }

    @MainActor static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }

    /// The full screen display: the one chosen in Settings, else an external one, else the main one.
    @MainActor static var fullScreen: NSScreen? {
        if let name = PrompterPreferences.fullScreenDisplay, let chosen = NSScreen.screens.first(where: { $0.localizedName == name }) {
            return chosen
        }
        return NSScreen.screens.first { CGDisplayIsBuiltin(displayID($0)) == 0 } ?? NSScreen.main
    }
}

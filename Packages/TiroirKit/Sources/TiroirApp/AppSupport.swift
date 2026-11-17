import AppKit
import TiroirUI

/// Switches read when the drawers start, from the command line or the defaults (`-ColDrawersDemo YES`). They let scripts
/// photograph the real drawers for the website and the README, and never touch the person's own menu bar in demo mode.
@available(macOS 26, *)
public struct LaunchOptions: Sendable {
    /// Generic icons instead of the menu bar's.
    public var demo: Bool
    /// Open the welcome at this step (0 to 3).
    public var welcomeStep: Int?
    /// Open Settings at this pane.
    public var settingsPane: SettingsPane?
    /// Open this drawer after launch (0 is the first; -1, or "all" on the command line, is the All drawer).
    public var openDrawer: Int?
    /// Open search with this text.
    public var search: String?
    /// Show windows without taking the keyboard or bringing Col to the front, for captures while someone works.
    public var quiet: Bool
    /// In demo mode, a picture to show behind the drawers' windows, so the glass of captures shows it and nothing else.
    public var backdrop: String?

    public static func current(_ defaults: UserDefaults = .standard) -> LaunchOptions {
        LaunchOptions(
            demo: defaults.bool(forKey: "ColDrawersDemo"),
            welcomeStep: integer("ColDrawersWelcomeStep", in: defaults),
            settingsPane: defaults.string(forKey: "ColDrawersPane").flatMap(SettingsPane.init(rawValue:)),
            openDrawer: defaults.string(forKey: "ColDrawersOpen") == "all" ? -1 : integer("ColDrawersOpen", in: defaults),
            search: defaults.string(forKey: "ColDrawersSearch"),
            quiet: defaults.bool(forKey: "ColDrawersQuiet"),
            backdrop: defaults.string(forKey: "ColDrawersBackdrop"))
    }

    /// A number given on the command line arrives as text (`-ColDrawersOpen 0`), one set with `defaults write` as a
    /// number: both count, and an absent key stays nil rather than zero.
    static func integer(_ key: String, in defaults: UserDefaults) -> Int? {
        if let number = defaults.object(forKey: key) as? Int { return number }
        return defaults.string(forKey: key).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// A still picture behind the drawers' windows, for captures in demo mode only: the glass then shows the picture, never
/// the windows of whoever runs the capture.
@available(macOS 26, *)
@MainActor
enum Backdrop {
    static func show(imageAt path: String) -> NSWindow? {
        guard let image = NSImage(contentsOfFile: path), let screen = NSScreen.main else { return nil }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        let view = NSImageView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.image = image
        view.imageScaling = .scaleAxesIndependently
        window.contentView = view
        window.orderFrontRegardless()
        return window
    }
}

/// What Col gives the drawers, which run in its process: where their settings live, Col's own way to ask for the one
/// permission and to move itself to /Applications, a Dock icon while one of their windows is open, and a word each time
/// the menu bar changed, so the island measures the room beside the notch again.
@available(macOS 26, *)
@MainActor
public struct DrawersHost {
    /// The preferences the settings live in, under `settingsKey`.
    public var defaults: UserDefaults
    public var settingsKey: String
    /// Asks for Accessibility (Device Control and Data Access on macOS 27) the way Col does everywhere else.
    public var requestAccessibility: () -> Void
    /// Moves Col to /Applications and opens it from there: macOS 27 honours only apps there.
    public var moveToApplications: () -> Void
    /// A window of the drawers opened, or closed.
    public var windowOpened: (NSWindow) -> Void
    public var windowClosed: (NSWindow) -> Void
    /// Icons moved, hid or came back, or the drawers' own items changed.
    public var menuBarChanged: () -> Void

    public init(defaults: UserDefaults, settingsKey: String, requestAccessibility: @escaping () -> Void = {},
                moveToApplications: @escaping () -> Void = {}, windowOpened: @escaping (NSWindow) -> Void = { _ in },
                windowClosed: @escaping (NSWindow) -> Void = { _ in }, menuBarChanged: @escaping () -> Void = {}) {
        self.defaults = defaults
        self.settingsKey = settingsKey
        self.requestAccessibility = requestAccessibility
        self.moveToApplications = moveToApplications
        self.windowOpened = windowOpened
        self.windowClosed = windowClosed
        self.menuBarChanged = menuBarChanged
    }
}

/// A menu item that runs a closure.
@available(macOS 26, *)
@MainActor
final class ActionItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, key: String = "", action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}

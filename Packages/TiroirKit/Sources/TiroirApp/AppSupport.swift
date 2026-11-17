import AppKit
import TiroirUI

/// Switches read at launch from the command line or the defaults (`-TiroirDemo YES`). They let scripts photograph the
/// real app for the website and the README, and never touch the person's own menu bar in demo mode.
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
    /// Show windows without taking the keyboard or bringing Tiroir to the front, for captures while someone works.
    public var quiet: Bool
    /// In demo mode, a picture to show behind Tiroir's windows, so the glass of captures shows it and nothing else.
    public var backdrop: String?

    public static func current(_ defaults: UserDefaults = .standard) -> LaunchOptions {
        LaunchOptions(
            demo: defaults.bool(forKey: "TiroirDemo"),
            welcomeStep: integer("TiroirWelcomeStep", in: defaults),
            settingsPane: defaults.string(forKey: "TiroirSettingsPane").flatMap(SettingsPane.init(rawValue:)),
            openDrawer: defaults.string(forKey: "TiroirOpenDrawer") == "all" ? -1 : integer("TiroirOpenDrawer", in: defaults),
            search: defaults.string(forKey: "TiroirSearch"),
            quiet: defaults.bool(forKey: "TiroirQuiet"),
            backdrop: defaults.string(forKey: "TiroirBackdrop"))
    }

    /// A number given on the command line arrives as text (`-TiroirOpenDrawer 0`), one set with `defaults write` as a
    /// number: both count, and an absent key stays nil rather than zero.
    static func integer(_ key: String, in defaults: UserDefaults) -> Int? {
        if let number = defaults.object(forKey: key) as? Int { return number }
        return defaults.string(forKey: key).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// A still picture behind Tiroir's windows, for captures in demo mode only: the glass then shows the picture, never
/// the windows of whoever runs the capture.
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

/// Software updates, which the app target provides with Sparkle; this package never imports it.
@MainActor
public protocol UpdateChecking: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    func start()
    func checkForUpdates()
}

/// The menu bar of Tiroir's own windows: About, Settings and Quit, the editing commands text fields need, and Close.
@MainActor
enum MainMenu {
    static func make(onSettings: @escaping () -> Void) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: Strings.aboutTiroir, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = ActionItem(title: Strings.settingsMenuItem, key: ",", action: onSettings)
        app.addItem(settings)
        app.addItem(.separator())
        app.addItem(withTitle: Strings.quitTiroir, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: Strings.appName))

        let edit = NSMenu()
        edit.addItem(withTitle: Strings.undo, action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: Strings.redo, action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: Strings.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: Strings.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: Strings.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: Strings.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, title: Strings.editMenu))

        let window = NSMenu()
        window.addItem(withTitle: Strings.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: Strings.minimize, action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu(window, title: Strings.windowMenu))
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }
}

/// A menu item that runs a closure.
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

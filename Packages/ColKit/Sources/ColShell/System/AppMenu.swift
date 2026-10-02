import AppKit

/// Col's menus. The menu bar shows them only while one of Col's windows is in front, but the shortcuts in them
/// (copy and paste in a text field, ⌘W, ⌘Q) work in every window.
@MainActor
public enum AppMenu {
    public static func install() {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(editMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Col")
        menu.addItem(item(String(localized: "About Col", bundle: .module), #selector(MenuActions.showAbout), target: MenuActions.shared))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…", bundle: .module), #selector(MenuActions.showSettings), key: ",", target: MenuActions.shared))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Hide Col", bundle: .module), #selector(NSApplication.hide(_:)), key: "h"))
        let others = item(String(localized: "Hide Others", bundle: .module), #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(others)
        menu.addItem(item(String(localized: "Show All", bundle: .module), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Col", bundle: .module), #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit", bundle: .module))
        menu.addItem(item(String(localized: "Undo", bundle: .module), Selector(("undo:")), key: "z"))
        let redo = item(String(localized: "Redo", bundle: .module), Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Cut", bundle: .module), #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item(String(localized: "Copy", bundle: .module), #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item(String(localized: "Paste", bundle: .module), #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item(String(localized: "Select All", bundle: .module), #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window", bundle: .module))
        menu.addItem(item(String(localized: "Minimize", bundle: .module), #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item(String(localized: "Zoom", bundle: .module), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Close", bundle: .module), #selector(NSWindow.performClose(_:)), key: "w"))
        return menu
    }

    private static func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}

@MainActor
private final class MenuActions: NSObject {
    static let shared = MenuActions()

    @objc func showAbout() { SettingsWindow.shared.show(.about) }
    @objc func showSettings() { SettingsWindow.shared.show() }
}

/// Col lives in the notch, without a Dock icon. While one of its windows is open it becomes an ordinary app, with a
/// Dock icon, a place in ⌘Tab and its menus, and goes back to the notch alone once the last one closes.
@MainActor
final class WindowPresence {
    static let shared = WindowPresence()
    private var windows: Set<ObjectIdentifier> = []

    func add(_ window: NSWindow) {
        windows.insert(ObjectIdentifier(window))
        update()
    }

    func remove(_ window: NSWindow) {
        windows.remove(ObjectIdentifier(window))
        update()
    }

    private func update() {
        let policy: NSApplication.ActivationPolicy = windows.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}

extension NSWindow {
    /// AppKit can hold on to a closed window, as the window that was key before it for one: emptied once closed, the
    /// window keeps nothing alive, and its views and their SwiftUI graph go with the close. Measured on the settings:
    /// what they leave behind falls from 54 to 44 MB (Release).
    func emptyWhenClosed() {
        DispatchQueue.main.async { [weak self] in
            self?.contentViewController = nil
            self?.contentView = NSView()
        }
    }
}

import AppKit
import IsletPrompter
import SwiftUI

/// The prompter's scripts: the list on the left, the script being written on the right with its play button. It opens
/// below the island like the settings, and remembers its size.
@MainActor
final class ScriptLibraryWindow: NSObject, NSWindowDelegate {
    static let shared = ScriptLibraryWindow()
    private var window: NSWindow?

    static let preferredSize = NSSize(width: 1000, height: 660)
    static let minimumSize = NSSize(width: 760, height: 460)

    func show() {
        let window = self.window ?? makeWindow()
        WindowPresence.shared.add(window)
        DispatchQueue.main.async {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: LibraryView(app: .shared).frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Scripts", bundle: .module)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
        window.minSize = Self.minimumSize
        window.delegate = self
        WindowPlacement.belowIsland(window, preferred: Self.preferredSize, minimum: Self.minimumSize, sizeKey: "scriptLibraryWindowSize")
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: "scriptLibraryWindowSize")
            WindowPresence.shared.remove(window)
        }
        PrompterCenter.shared.store.flush()
        window = nil
    }
}

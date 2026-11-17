import AppKit
import TiroirCore
import TiroirSystem

/// Show Every Icon from the menu bar itself, and hiding them again (spec 6.3, Behavior). A rest, a click or a scroll
/// on empty room shows every icon; once every icon shows, they hide again after the pointer has been away from the
/// menu bar for a few seconds with no menu open. The watch runs only while every icon shows.
@MainActor
final class RevealController {
    /// A rest or a click on empty room: show every icon.
    var onReveal: (() -> Void)?
    /// A scroll on empty room: show every icon, or hide them again.
    var onToggle: (() -> Void)?
    /// Time to hide them again.
    var onHideAgain: (() -> Void)?

    let watcher = MenuBarWatcher()
    private var behavior = Behavior()
    private var countdown: Task<Void, Never>?

    static let tick: Duration = .milliseconds(500)

    init() {
        watcher.onHover = { [weak self] in self?.onReveal?() }
        watcher.onClick = { [weak self] in self?.onReveal?() }
        watcher.onScroll = { [weak self] in self?.onToggle?() }
    }

    func configure(_ behavior: Behavior) {
        self.behavior = behavior
        watcher.watch(hover: behavior.revealsOnHover, click: behavior.revealsOnClick, scroll: behavior.revealsOnScroll,
                      hoverDelay: behavior.hoverDelay)
        if !behavior.hidesAgainAutomatically { countdown?.cancel() }
    }

    /// Every icon started or stopped showing in the menu bar.
    func everythingShows(_ shows: Bool) {
        countdown?.cancel()
        countdown = nil
        guard shows, behavior.hidesAgainAutomatically else { return }
        let delay = Duration.milliseconds(Int(behavior.hideAgainDelay * 1000))
        countdown = Task { [weak self] in
            var lastUse = ContinuousClock.now
            while !Task.isCancelled {
                if Self.personUsesTheMenuBar() { lastUse = .now }
                if ContinuousClock.now - lastUse >= delay {
                    self?.countdown = nil
                    self?.onHideAgain?()
                    return
                }
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    /// The pointer on a menu bar, a menu or a panel open from it, or a button held down.
    static func personUsesTheMenuBar() -> Bool {
        if NSEvent.pressedMouseButtons != 0 { return true }
        let pointer = NSEvent.mouseLocation
        let onABar = NSScreen.screens.contains { screen in
            NSMouseInRect(pointer, screen.frame, false) && pointer.y >= screen.visibleFrame.maxY - 1
        }
        return onABar || SystemStatusWindows.anyMenuIsOpen()
    }
}

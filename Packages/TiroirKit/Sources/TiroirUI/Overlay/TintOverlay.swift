import AppKit
import QuartzCore
import TiroirCore
import TiroirSystem

/// The menu bar's tint, border and shadow (spec 6.3, Appearance). One window per display, just below the menu bar's
/// level: on macOS 26 and 27 the bar has no background by default, so the tint shows through, and the icons stay on
/// top of it. It never takes a click.
///
/// A window is drawn again only when what it shows changes. With nothing to draw, the overlay watches nothing. With a
/// dark look it follows the system's appearance; with the split shape on a display without a notch it reads where the
/// front app's menus end each time another app comes to the front, and takes where the icons start from the
/// coordinator's scans.
@MainActor
public final class TintOverlay {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    /// What each window shows, so an update that changes nothing draws nothing.
    private var drawn: [CGDirectDisplayID: Drawing] = [:]
    private var appearance = Appearance.standard
    private var isDark = false
    /// Where the icons start on each display, from the coordinator's last scan.
    private var statusStarts: [CGDirectDisplayID: CGFloat] = [:]
    /// The front app's menus, in AppKit coordinates.
    private var menus: [CGRect] = []
    private var appearanceObservation: NSKeyValueObservation?
    private var frontAppObserver: NSObjectProtocol?
    private var menusReading: Task<Void, Never>?

    /// What one window shows.
    struct Drawing: Equatable {
        var frame: CGRect
        var look: Appearance.Look
        var pieces: TintGeometry.Pieces
        var scale: CGFloat
    }

    public init() {}

    isolated deinit {
        stopWatchingFrontApp()
    }

    /// Shows `appearance`, on every display that has a menu bar.
    public func update(_ appearance: Appearance) {
        self.appearance = appearance
        watchSystemAppearance(Self.watchesSystemAppearance(for: appearance))
        render()
    }

    /// Where the icons start on each display, in AppKit coordinates: the split shape's right piece starts a little
    /// left of it. The coordinator measures it after each scan of the menu bar.
    public func update(statusStarts: [CGDirectDisplayID: CGFloat]) {
        guard statusStarts != self.statusStarts else { return }
        self.statusStarts = statusStarts
        if appearance.shape == .split { render() }
    }

    /// Takes every window down and stops watching (on quit).
    public func removeAll() {
        watchSystemAppearance(false)
        stopWatchingFrontApp()
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        drawn.removeAll()
    }

    /// Whether the system's appearance matters: only with a dark look, and something to draw.
    static func watchesSystemAppearance(for appearance: Appearance) -> Bool {
        appearance.darkLook != nil && appearance.isVisible
    }

    /// Whether the front app's menus matter: only for the split shape on a display without a notch (beside a notch,
    /// the pieces end at the notch).
    static func watchesFrontApp(for shape: Appearance.Shape, screensWithoutNotch: Int) -> Bool {
        shape == .split && screensWithoutNotch > 0
    }

    /// Whether the Mac is in Dark Mode.
    static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: Drawing

    private func render() {
        let look = appearance.look(inDarkMode: isDark)
        guard look.isVisible else {
            stopWatchingFrontApp()
            removeWindows(except: [])
            return
        }
        let screens = NSScreen.screens
        if Self.watchesFrontApp(for: appearance.shape, screensWithoutNotch: screens.filter { !$0.hasNotch }.count) {
            startWatchingFrontApp()
        } else {
            stopWatchingFrontApp()
        }
        var shown: Set<CGDirectDisplayID> = []
        for screen in screens {
            guard let id = screen.displayID else { continue }
            let bar = screen.menuBarFrame
            guard bar.height > 0 else { continue }
            shown.insert(id)
            let pieces = TintGeometry.pieces(
                for: appearance.shape, screen: screen.frame, menuBarHeight: bar.height,
                notchLeft: screen.auxiliaryTopLeftArea, notchRight: screen.auxiliaryTopRightArea,
                menusEnd: TintGeometry.menusEnd(of: menus, in: bar), statusStart: statusStarts[id])
            let drawing = Drawing(frame: TintLayers.windowFrame(menuBar: bar, look: look), look: look, pieces: pieces,
                                  scale: screen.backingScaleFactor)
            guard drawn[id] != drawing else { continue }
            let window = windows[id] ?? Self.makeWindow()
            windows[id] = window
            window.setFrame(drawing.frame, display: false)
            if let layer = window.contentView?.layer {
                TintLayers.draw(look, in: pieces, frame: drawing.frame, scale: drawing.scale, on: layer)
            }
            drawn[id] = drawing
            window.orderFrontRegardless()
        }
        removeWindows(except: shown)
    }

    private func removeWindows(except kept: Set<CGDirectDisplayID>) {
        for (id, window) in windows where !kept.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
            drawn[id] = nil
        }
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        window.contentView = view
        return window
    }

    // MARK: Light and Dark Mode

    private func watchSystemAppearance(_ watching: Bool) {
        guard watching else {
            appearanceObservation?.invalidate()
            appearanceObservation = nil
            return
        }
        isDark = Self.systemIsDark
        guard appearanceObservation == nil else { return }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.systemAppearanceChanged() }
        }
    }

    private func systemAppearanceChanged() {
        let dark = Self.systemIsDark
        guard dark != isDark else { return }
        isDark = dark
        render()
    }

    // MARK: The front app's menus

    private func startWatchingFrontApp() {
        guard frontAppObserver == nil else { return }
        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The menu bar shows the new app's menus a moment after the app comes to the front.
            Task { @MainActor in self?.readMenus(after: .milliseconds(200)) }
        }
        readMenus(after: .zero)
    }

    private func stopWatchingFrontApp() {
        menusReading?.cancel()
        menusReading = nil
        menus = []
        guard let frontAppObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(frontAppObserver)
        self.frontAppObserver = nil
    }

    /// Reads the front app's menus away from the main actor (each read is a round trip to the app), then draws again
    /// if they moved.
    private func readMenus(after delay: Duration) {
        menusReading?.cancel()
        menusReading = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            let frames = await Task.detached { AppMenus.frames(of: pid) }.value
            guard !Task.isCancelled, let self else { return }
            let menus = frames.map(ScreenCoordinates.appKitRect(fromWindowServer:))
            guard menus != self.menus else { return }
            self.menus = menus
            render()
        }
    }
}

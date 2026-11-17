import AppKit
import CoreGraphics

/// Hears the pointer on the menu bar for Show Every Icon (spec 6.3, Behavior): a rest, a click or a scroll on an
/// empty part of the bar. Global monitors of mouse events need no permission and only see what happens outside
/// Tiroir's own windows. Only the monitors a setting asks for run: with the defaults, nothing listens.
@MainActor
public final class MenuBarWatcher {
    public var onHover: (@MainActor () -> Void)?
    public var onClick: (@MainActor () -> Void)?
    public var onScroll: (@MainActor () -> Void)?
    /// What the menu bar holds besides empty room, in AppKit coordinates: every icon, Tiroir's own items included.
    /// The coordinator updates it after each scan.
    public var occupied: [CGRect] = []

    private var monitors: [Any] = []
    private var activation: NSObjectProtocol?
    private var menusEnd: (screen: CGRect, x: CGFloat)?
    private var resting: Task<Void, Never>?
    private var hoverDelay: Duration = .milliseconds(250)
    private var lastScroll: ContinuousClock.Instant?

    /// One swipe sends dozens of scroll events: they count once.
    static let scrollPause: Duration = .milliseconds(700)

    public init() {}

    public var isWatching: Bool { !monitors.isEmpty }

    /// Listens for exactly what is asked, and for nothing when nothing is.
    public func watch(hover: Bool, click: Bool, scroll: Bool, hoverDelay: TimeInterval) {
        stop()
        guard hover || click || scroll else { return }
        self.hoverDelay = .milliseconds(Int(hoverDelay * 1000))
        if hover, let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            guard !Self.isTiroirs(event) else { return }
            Task { @MainActor in self?.pointerMoved() }
        }) {
            monitors.append(monitor)
        }
        if click, let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            guard !Self.isTiroirs(event) else { return }
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.clicked(at: point) }
        }) {
            monitors.append(monitor)
        }
        if scroll, let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard !Self.isTiroirs(event) else { return }
            let point = NSEvent.mouseLocation
            let isGesture = event.deltaY != 0 || event.scrollingDeltaY != 0
            Task { @MainActor in if isGesture { self?.scrolled(at: point) } }
        }) {
            monitors.append(monitor)
        }
        // The front app's menus take the left of the bar, and change with the front app.
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.measureMenus() }
        }
        measureMenus()
    }

    public func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        resting?.cancel()
        resting = nil
    }

    // MARK: Events

    /// Tiroir's own Command-drags carry its mark: they are never the person asking for every icon.
    nonisolated static func isTiroirs(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == SystemEventPoster.userDataMarker
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        guard isEmpty(point) else {
            resting?.cancel()
            resting = nil
            return
        }
        guard resting == nil else { return }
        resting = Task { [weak self, hoverDelay] in
            try? await Task.sleep(for: hoverDelay)
            guard let self, !Task.isCancelled else { return }
            self.resting = nil
            // Still on empty room, and not dragging anything.
            if NSEvent.pressedMouseButtons == 0, self.isEmpty(NSEvent.mouseLocation) { self.onHover?() }
        }
    }

    private func clicked(at point: CGPoint) {
        if isEmpty(point) { onClick?() }
    }

    private func scrolled(at point: CGPoint) {
        guard isEmpty(point) else { return }
        let now = ContinuousClock.now
        defer { lastScroll = now }
        if let lastScroll, now - lastScroll < Self.scrollPause { return }
        onScroll?()
    }

    // MARK: Geometry

    private func isEmpty(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return false }
        let menus = menusEnd.flatMap { $0.screen == screen.frame ? $0.x : nil }
        return Self.isEmptySpot(point, screen: screen.frame, barBottom: screen.visibleFrame.maxY, menusEnd: menus,
                                occupied: occupied)
    }

    /// Whether a point (AppKit coordinates) is on the empty part of a menu bar: on the bar, right of the front app's
    /// menus, and on no icon. On a screen where the menus were not measured, only the right half counts, which the
    /// app menus rarely reach.
    nonisolated static func isEmptySpot(_ point: CGPoint, screen: CGRect, barBottom: CGFloat, menusEnd: CGFloat?,
                                        occupied: [CGRect]) -> Bool {
        guard screen.contains(point), point.y >= barBottom - 1 else { return false }
        let leftLimit = menusEnd.map { $0 + 8 } ?? screen.midX
        guard point.x > leftLimit else { return false }
        return !occupied.contains { $0.insetBy(dx: -4, dy: -2).contains(point) }
    }

    /// Where the front app's menus end, read through Accessibility away from the main actor. The x axis is the same in
    /// AppKit's and the window server's coordinates.
    private func measureMenus() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            menusEnd = nil
            return
        }
        let pid = app.processIdentifier
        Task.detached { [weak self] in
            let frames = AppMenus.frames(of: pid)
            await MainActor.run { self?.menusMeasured(frames) }
        }
    }

    private func menusMeasured(_ frames: [CGRect]) {
        guard let last = frames.max(by: { $0.maxX < $1.maxX }) else {
            menusEnd = nil
            return
        }
        let appKit = ScreenCoordinates.appKitRect(fromWindowServer: last)
        let middle = CGPoint(x: appKit.midX, y: appKit.midY)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(middle, $0.frame, false) }) else {
            menusEnd = nil
            return
        }
        menusEnd = (screen.frame, last.maxX)
    }
}

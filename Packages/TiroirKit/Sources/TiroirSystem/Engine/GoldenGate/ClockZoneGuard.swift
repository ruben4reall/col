import AppKit

/// Keeps Notification Center working on macOS 27 (spec 4.4, The clock).
///
/// While MenuBarAgent holds a restriction, a click on the clock does not open Notification Center, and MenuBarAgent
/// decides at the press, so lifting the restriction then is too late. The guard lifts it while the pointer rests on
/// the clock and puts it back half a second after the pointer leaves. It watches the pointer only while something is
/// hidden, through a global mouse-move monitor, which needs no permission. Technique from MenuBarHider (MIT),
/// rewritten.
@MainActor
public final class ClockZoneGuard {
    /// Called with true when the pointer arrives on the clock, false half a second after it leaves.
    public var onChange: (@MainActor (Bool) -> Void)?
    /// The clock and the room around it, in window server coordinates; nil means the trailing 240 points.
    public var clockFrame: CGRect?

    public private(set) var isOverClock = false
    private var monitor: Any?
    private var leaving: Task<Void, Never>?

    static let defaultZoneWidth: CGFloat = 240
    static let margin: CGFloat = 24
    static let grace: Duration = .milliseconds(500)

    public init() {}

    public var isActive: Bool { monitor != nil }

    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        update()
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        leaving?.cancel()
        leaving = nil
        if isOverClock {
            isOverClock = false
            onChange?(false)
        }
    }

    func update() {
        let inside = Self.contains(pointer: NSEvent.mouseLocation, clock: clockFrame)
        if inside {
            leaving?.cancel()
            leaving = nil
            if !isOverClock {
                isOverClock = true
                onChange?(true)
            }
        } else if isOverClock, leaving == nil {
            leaving = Task { [weak self] in
                try? await Task.sleep(for: Self.grace)
                guard let self, !Task.isCancelled else { return }
                self.leaving = nil
                self.isOverClock = false
                self.onChange?(false)
            }
        }
    }

    /// Whether the pointer (AppKit coordinates) is on the clock's part of a menu bar.
    static func contains(pointer: CGPoint, clock: CGRect?) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else { return false }
        let barBottom = screen.visibleFrame.maxY
        guard pointer.y >= barBottom - 1 else { return false }
        if let clock {
            let appKitClock = ScreenCoordinates.appKitRect(fromWindowServer: clock)
            return pointer.x >= appKitClock.minX - margin && pointer.x <= screen.frame.maxX
        }
        return pointer.x >= screen.frame.maxX - defaultZoneWidth
    }
}

import AppKit
import CoreGraphics

/// Where synthetic events enter the system. Menu bar managers disagree, and what works can change with a macOS
/// update, so Tiroir tries them in this order and remembers the one that worked.
public enum PostingRoute: String, CaseIterable, Sendable {
    /// The session event tap, as if a person had moved the mouse.
    case session
    /// Straight to the process that owns the icon's window (Control Center on macOS 26).
    case owner
    /// The HID tap, below everything else.
    case hid
}

/// Posts the synthetic mouse events that move and click icons on macOS 26. The system implementation talks to the
/// window server; tests use a simulated menu bar.
@MainActor
public protocol EventPosting: AnyObject {
    /// A Command-drag of the icon window `windowID` from `start` to `end`, the way people rearrange the menu bar.
    func commandDrag(windowID: UInt32, ownerPID: pid_t, from start: CGPoint, to end: CGPoint, destinationWindowID: UInt32?, route: PostingRoute) async
    /// A plain click on the icon window `windowID`.
    func click(windowID: UInt32, ownerPID: pid_t, at point: CGPoint, route: PostingRoute) async
}

/// Whether the person is using the mouse or the keyboard right now.
public protocol UserActivitySource: Sendable {
    var secondsSincePointerMoved: TimeInterval { get }
    var isMouseButtonDown: Bool { get }
    var areModifiersDown: Bool { get }
}

public struct SystemUserActivity: UserActivitySource {
    public init() {}

    /// A modifier seen held with no key event for this long is a state some software left behind (a synthetic press
    /// with no release), not a person about to use a shortcut.
    static let staleAfter: TimeInterval = 10

    public var secondsSincePointerMoved: TimeInterval {
        let moved = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let dragged = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDragged)
        return min(moved, dragged)
    }

    public var isMouseButtonDown: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
    }

    public var areModifiersDown: Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let held = !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
        guard held else { return false }
        let lastKey = [CGEventType.flagsChanged, .keyDown, .keyUp]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
        return Self.isPersonHolding(modifiers: held, secondsSinceKeyEvent: lastKey)
    }

    /// Modifiers count as held by a person only while keys are in use.
    static func isPersonHolding(modifiers: Bool, secondsSinceKeyEvent: TimeInterval) -> Bool {
        modifiers && secondsSinceKeyEvent < staleAfter
    }
}

/// The recipe, as the working menu bar managers use it on macOS 26:
/// - events come from a HID system state source and go to the session event tap and to the window's owner (Control
///   Center hosts every icon's window on 26);
/// - every event names the icon's window in the "window under the pointer" fields, so the press does not need to land
///   on the icon, which may be off screen;
/// - the press carries Command, the release does not;
/// - the pointer is hidden during the move, then put back where it was.
@MainActor
public final class SystemEventPoster: EventPosting {
    /// Undocumented field that also carries the window under the pointer.
    static let windowUnderPointerField = CGEventField(rawValue: 51)
    /// Marks Tiroir's own events, for anyone watching the event stream.
    nonisolated static let userDataMarker: Int64 = 0x7A6E_7375 // "znsu" in ASCII: a value no other app uses

    private let source = CGEventSource(stateID: .hidSystemState)

    public init() {
        // Keep the person's real input flowing while Tiroir posts its own events.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateRemoteMouseDrag)
        source?.localEventsSuppressionInterval = 0
        PrivateAPI.allowCursorChangesInBackground()
    }

    public func commandDrag(windowID: UInt32, ownerPID: pid_t, from start: CGPoint, to end: CGPoint, destinationWindowID: UInt32?, route: PostingRoute) async {
        await withHiddenPointer(at: ScreenCoordinates.isOnScreen(CGRect(origin: start, size: CGSize(width: 1, height: 1))) ? start : nil) {
            post(.leftMouseDown, at: start, window: windowID, owner: ownerPID, flags: .maskCommand, route: route)
            try? await Task.sleep(for: .milliseconds(20))
            let steps = 4
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                post(.leftMouseDragged, at: point, window: windowID, owner: ownerPID, flags: .maskCommand, route: route)
                try? await Task.sleep(for: .milliseconds(8))
            }
            post(.leftMouseUp, at: end, window: destinationWindowID ?? windowID, owner: ownerPID, flags: [], route: route)
            try? await Task.sleep(for: .milliseconds(15))
            // A second release costs nothing and saves a drag left hanging if the first was dropped.
            post(.leftMouseUp, at: end, window: destinationWindowID ?? windowID, owner: ownerPID, flags: [], route: route)
        }
    }

    public func click(windowID: UInt32, ownerPID: pid_t, at point: CGPoint, route: PostingRoute) async {
        await withHiddenPointer(at: point) {
            post(.leftMouseDown, at: point, window: windowID, owner: ownerPID, flags: [], route: route)
            try? await Task.sleep(for: .milliseconds(30))
            post(.leftMouseUp, at: point, window: windowID, owner: ownerPID, flags: [], route: route)
        }
    }

    private func post(_ type: CGEventType, at point: CGPoint, window: UInt32, owner: pid_t, flags: CGEventFlags, route: PostingRoute) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = flags
        let windowNumber = Int64(window)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowNumber)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowNumber)
        if let field = Self.windowUnderPointerField { event.setIntegerValueField(field, value: windowNumber) }
        event.setIntegerValueField(.eventSourceUserData, value: Self.userDataMarker)
        if type == .leftMouseDown || type == .leftMouseUp {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        switch route {
        case .session: event.post(tap: .cgSessionEventTap)
        case .owner: event.postToPid(owner)
        case .hid: event.post(tap: .cghidEventTap)
        }
    }

    /// Hides the pointer, moves it to `point` when that is on screen (the window server may route events by where the
    /// pointer really is), runs `body`, then puts the pointer back and shows it.
    private func withHiddenPointer(at point: CGPoint?, _ body: () async -> Void) async {
        let saved = CGEvent(source: nil)?.location
        let display = CGMainDisplayID()
        CGDisplayHideCursor(display)
        if let point {
            CGWarpMouseCursorPosition(point)
            try? await Task.sleep(for: .milliseconds(12))
        }
        await body()
        if let saved { CGWarpMouseCursorPosition(saved) }
        CGAssociateMouseAndMouseCursorPosition(1)
        CGDisplayShowCursor(display)
    }
}

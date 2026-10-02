/// Something that happened to the island.
public enum IslandEvent: Sendable, Equatable {
    case pointerEntered
    case pointerExited
    case pressed
    case swipedDown
    case swipedUp
    case dismissed
    /// Something needs the user, such as an agent asking for permission: the island opens by itself.
    case requested
    /// The pointer has rested on the peeking island long enough to open it.
    case hoverTimerFired
    /// The pointer left the open island and stayed away for the grace period.
    case exitTimerFired
}

/// Work the machine asks its host to do. Timers live outside so the rules stay deterministic.
public enum IslandEffect: Sendable, Equatable {
    case startHoverTimer
    case cancelHoverTimer
    case startExitTimer
    case cancelExitTimer
    case haptic
}

/// The rules that open and close the island.
///
/// Resting on the notch makes it peek, then open after a short dwell. A click or a two-finger swipe down opens it at
/// once. Once open it stays open while the pointer is over it, and closes shortly after the pointer leaves, so a
/// pointer that slips off the edge for an instant does not slam it shut. A swipe up closes it straight away.
public struct IslandMachine: Sendable {
    public private(set) var state: IslandState = .collapsed
    public private(set) var pointerInside = false
    public var opensOnHover: Bool

    public init(opensOnHover: Bool = true) {
        self.opensOnHover = opensOnHover
    }

    public mutating func handle(_ event: IslandEvent) -> [IslandEffect] {
        switch event {
        case .pointerEntered:
            pointerInside = true
            switch state {
            case .collapsed:
                state = .peek
                return opensOnHover ? [.startHoverTimer] : []
            case .peek:
                return []
            case .expanded:
                return [.cancelExitTimer]
            }

        case .pointerExited:
            pointerInside = false
            switch state {
            case .collapsed:
                return []
            case .peek:
                state = .collapsed
                return [.cancelHoverTimer]
            case .expanded:
                return [.startExitTimer]
            }

        case .pressed, .swipedDown, .requested:
            guard state != .expanded else { return [] }
            state = .expanded
            return [.cancelHoverTimer, .haptic]

        case .hoverTimerFired:
            guard state == .peek, pointerInside else { return [] }
            state = .expanded
            return [.haptic]

        case .exitTimerFired:
            guard state == .expanded, !pointerInside else { return [] }
            state = .collapsed
            return []

        case .swipedUp, .dismissed:
            guard state != .collapsed else { return [] }
            state = .collapsed
            return [.cancelHoverTimer, .cancelExitTimer]
        }
    }
}

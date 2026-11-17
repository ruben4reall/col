import Foundation

/// What the triggers that hold ask of the menu bar, all together.
public struct TriggerEffect: Equatable, Sendable {
    /// Focus: only the clock and Control Center stay. It wins over the icons triggers show.
    public var focus: Bool
    /// Icons that show in the menu bar whatever their place.
    public var icons: Set<IconID>
    /// Drawers whose icons show in the menu bar.
    public var drawers: Set<UUID>

    public init(focus: Bool = false, icons: Set<IconID> = [], drawers: Set<UUID> = []) {
        self.focus = focus
        self.icons = icons
        self.drawers = drawers
    }

    public static let none = TriggerEffect()

    /// What the planner is given: a mode, and icons shown on top of the layout.
    public struct Planning: Equatable, Sendable {
        public var mode: LayoutPlanner.Mode
        public var icons: Set<IconID>
        public var drawers: Set<UUID>
    }

    /// How the planner runs for the person's own mode and this effect. The person's Focus or Show Every Icon wins over
    /// every trigger while it is on; a trigger's Focus wins over the icons triggers show; shown icons add up.
    public func planning(over mode: LayoutPlanner.Mode) -> Planning {
        if mode != .normal { return Planning(mode: mode, icons: [], drawers: []) }
        if focus { return Planning(mode: .focus, icons: [], drawers: []) }
        return Planning(mode: .normal, icons: icons, drawers: drawers)
    }
}

/// The order in which the triggers that hold started to hold, kept from one evaluation to the next while Tiroir runs.
public struct TriggerState: Equatable, Sendable {
    /// For each trigger that holds, when it started, as a sequence number: the higher, the more recent.
    public var started: [UUID: Int]
    var sequence: Int

    public init() {
        started = [:]
        sequence = 0
    }
}

/// A change of profile decided by the triggers.
public enum ProfileChange: Equatable, Sendable {
    /// Switch to this profile.
    case switchTo(UUID)
    /// Bring back what was there before the triggers switched.
    case restore(PreviousSetup)
}

/// One evaluation of the triggers.
public struct TriggerOutcome: Equatable, Sendable {
    /// Triggers that can act and whose condition holds: Settings marks them "Active now".
    public var active: Set<UUID>
    /// What they ask of the menu bar. Empty while the person's own Focus or Show Every Icon is on.
    public var effect: TriggerEffect
    /// The profile to switch to, or what to bring back, when that changes.
    public var profileChange: ProfileChange?
    /// The memory to keep in the settings.
    public var memory: TriggerMemory
    /// The order to give the next evaluation.
    public var state: TriggerState
}

/// Decides what the triggers do (spec: Triggers). Pure: the same settings, facts and state give the same outcome.
///
/// - Focus wins over the icons triggers show, and shown icons add up.
/// - For profiles, the trigger that started to hold last wins. When no trigger asks for a profile any more, the setup
///   that was there before the first one switched comes back, unless the person switched profiles by hand in between:
///   then theirs stays, and the triggers holding at that moment switch nothing more until their condition ends.
/// - The person's own Focus or Show Every Icon wins over every trigger while it is on.
/// - A trigger that is off, or whose profile or drawer no longer exists, does nothing.
public enum TriggerEvaluator {
    /// Whether a trigger can act in these settings: it is on, and its profile or drawer exists. An icon need not be in
    /// the menu bar right now: showing the icon of an app that does not run shows nothing, and does no harm.
    public static func canAct(_ trigger: Trigger, in settings: TiroirSettings) -> Bool {
        guard trigger.isEnabled else { return false }
        switch trigger.action {
        case .switchProfile(let id): return settings.profile(id) != nil
        case .showDrawer(let id): return settings.layout.drawer(id) != nil
        case .showIcon, .focus: return true
        }
    }

    /// - Parameters:
    ///   - state: the previous evaluation's order; a fresh state after a launch.
    ///   - isSuspended: the person's own Focus or Show Every Icon is on. Triggers then change nothing, but keep count of
    ///     what holds and notice a profile switched by hand.
    public static func evaluate(
        _ settings: TiroirSettings, facts: TriggerFacts, state: TriggerState = TriggerState(), isSuspended: Bool = false
    ) -> TriggerOutcome {
        let holding = settings.triggers.filter { canAct($0, in: settings) && $0.condition.holds(in: facts) }
        let holdingIDs = Set(holding.map(\.id))
        var memory = settings.triggerMemory

        // Triggers that held before keep their number; those starting now follow in list order, except the trigger
        // whose profile is in place (Tiroir restarted in the middle of it), which counts as the most recent.
        var next = state
        next.started = state.started.filter { holdingIDs.contains($0.key) }
        let held = memory.hold?.trigger
        let newcomers = holding.enumerated()
            .filter { next.started[$0.element.id] == nil }
            .sorted { ($0.element.id == held ? 1 : 0, $0.offset) < ($1.element.id == held ? 1 : 0, $1.offset) }
        for (_, trigger) in newcomers {
            next.sequence += 1
            next.started[trigger.id] = next.sequence
        }

        // A trigger forgets it was overruled once its condition ends.
        memory.overruled.formIntersection(holdingIDs)

        // The person switched profiles by hand while a trigger's profile was in place: their choice stays.
        if let hold = memory.hold, settings.activeProfile != hold.profile {
            memory.hold = nil
            memory.overruled.formUnion(holdingIDs)
        }

        guard !isSuspended else {
            return TriggerOutcome(active: holdingIDs, effect: .none, profileChange: nil, memory: memory, state: next)
        }

        var effect = TriggerEffect()
        for trigger in holding {
            switch trigger.action {
            case .focus: effect.focus = true
            case .showDrawer(let id): effect.drawers.insert(id)
            case .showIcon(let id): effect.icons.insert(id)
            case .switchProfile: break
            }
        }

        let wanted = holding
            .compactMap { trigger -> (trigger: UUID, profile: UUID, started: Int)? in
                guard case .switchProfile(let profile) = trigger.action, !memory.overruled.contains(trigger.id) else { return nil }
                return (trigger.id, profile, next.started[trigger.id] ?? 0)
            }
            .max { $0.started < $1.started }

        var change: ProfileChange?
        switch (wanted, memory.hold) {
        case (nil, nil):
            break
        case (nil, let hold?):
            if hold.previous != .profile(hold.profile) { change = .restore(hold.previous) }
            memory.hold = nil
        case (let wanted?, nil):
            let previous = settings.activeProfile.map(PreviousSetup.profile) ?? .setup(settings.layout, settings.appearance)
            memory.hold = ProfileHold(trigger: wanted.trigger, profile: wanted.profile, previous: previous)
            if settings.activeProfile != wanted.profile { change = .switchTo(wanted.profile) }
        case (let wanted?, var hold?):
            // Another trigger took over: what comes back at the end is still what was there before the first one.
            if hold.profile != wanted.profile { change = .switchTo(wanted.profile) }
            hold.trigger = wanted.trigger
            hold.profile = wanted.profile
            memory.hold = hold
        }
        return TriggerOutcome(active: holdingIDs, effect: effect, profileChange: change, memory: memory, state: next)
    }
}

extension TiroirSettings {
    /// Takes in an evaluation of the triggers: its change of profile, and the memory for the next one.
    public mutating func apply(_ outcome: TriggerOutcome) {
        switch outcome.profileChange {
        case .switchTo(let id)?, .restore(.profile(let id))?: switchProfile(to: id)
        case .restore(.setup(let layout, let appearance))?: restoreSetup(layout: layout, appearance: appearance)
        case nil: break
        }
        triggerMemory = outcome.memory
    }
}

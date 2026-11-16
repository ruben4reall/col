import AppKit
import ColCore
import Observation

/// Pomodoro: focus, then a break, counted in the wings like the timer. Nothing ticks: one task wakes up when a phase
/// ends, with a gentle sound. A break ends the cycle, so a Pomodoro never runs on while you are away.
@MainActor
@Observable
final class PomodoroModel {
    private(set) var session: Pomodoro?
    private(set) var tally: PomodoroTally
    @ObservationIgnored var post: ((Activity) -> Void)?
    @ObservationIgnored var remove: ((String) -> Void)?
    @ObservationIgnored private var alarm: Task<Void, Never>?

    private static let tallyKey = "pomodoroTally"
    static let focusTint = RGBA.red
    static let restTint = RGBA.green

    init() {
        tally = UserDefaults.standard.data(forKey: Self.tallyKey).flatMap { try? JSONDecoder().decode(PomodoroTally.self, from: $0) } ?? PomodoroTally()
    }

    /// Focus sessions completed today.
    var todayCount: Int { tally.count(on: Date()) }

    var plan: PomodoroPlan { Preferences.pomodoroPlan }

    func start() {
        session = Pomodoro(phase: .focus, plan: plan, starting: Date())
        schedule()
    }

    func togglePause() {
        guard var session else { return }
        let now = Date()
        if session.countdown.isPaused { session.countdown.resume(at: now) } else { session.countdown.pause(at: now) }
        self.session = session
        schedule()
    }

    /// Ends the phase now: a focus cut short goes to its break without counting, a break ends the cycle.
    func skip() {
        guard let session else { return }
        alarm?.cancel()
        self.session = session.next(plan: plan, at: Date())
        if self.session == nil { remove?("pomodoro") } else { schedule() }
    }

    func stop() {
        alarm?.cancel()
        session = nil
        remove?("pomodoro")
    }

    /// Turned off in the settings: a session under way stops.
    func preferencesChanged() {
        if !Preferences.showsPomodoro, session != nil { stop() }
    }

    static func tint(for phase: PomodoroPhase) -> RGBA { phase == .focus ? focusTint : restTint }
    static func symbol(for phase: PomodoroPhase) -> String { phase == .focus ? "brain.head.profile.fill" : "cup.and.heat.waves.fill" }

    private func schedule() {
        alarm?.cancel()
        guard let session else { return }
        let now = Date()
        let tint = Self.tint(for: session.phase)
        if session.countdown.isPaused {
            post?(Activity(
                id: "pomodoro", priority: .standard,
                compact: CompactPresentation(leading: .symbol("pause.fill", tint: tint), trailing: .ring(progress: session.countdown.fraction(at: now), tint: tint)),
                updated: now
            ))
            return
        }
        guard let ends = session.countdown.ends else { return }
        post?(Activity(
            id: "pomodoro", priority: .standard,
            compact: CompactPresentation(
                leading: .symbol(Self.symbol(for: session.phase), tint: tint),
                trailing: .countdown(ends: ends, total: session.countdown.total, tint: tint)
            ),
            updated: now
        ))
        alarm = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(ends.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.ring()
        }
    }

    private func ring() {
        guard let finished = session else { return }
        let now = Date()
        if finished.phase == .focus {
            tally.add(at: now)
            UserDefaults.standard.set(try? JSONEncoder().encode(tally), forKey: Self.tallyKey)
        }
        session = finished.next(plan: plan, at: now)
        NSSound(named: "Purr")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        let next = session?.phase
        let message = next == .rest
            ? String(localized: "Time for a break", bundle: .module)
            : String(localized: "Break over", bundle: .module)
        let tint = Self.tint(for: next ?? .focus)
        // Said for a moment, as an alert; the next phase, if any, counts down once it has been said.
        post?(Activity(
            id: "pomodoro.end", priority: .alert,
            compact: CompactPresentation(leading: .symbol(Self.symbol(for: next ?? .focus), tint: tint), trailing: .text(message, tint: tint)),
            expires: now.addingTimeInterval(5),
            updated: now
        ))
        if session == nil { remove?("pomodoro") } else { schedule() }
    }

    /// For screenshots: a session under way, without its wake-up.
    func showDemo(_ session: Pomodoro?, completed: Int) {
        self.session = session
        tally = PomodoroTally(day: PomodoroTally.key(for: Date()), count: completed)
    }
}

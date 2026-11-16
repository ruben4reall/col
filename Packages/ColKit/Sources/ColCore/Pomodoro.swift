import Foundation

/// How long a Pomodoro's focus and break last, in minutes.
public struct PomodoroPlan: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var breakMinutes: Int

    public static let standard = PomodoroPlan(focusMinutes: 25, breakMinutes: 5)
    public static let focusRange = 5...90
    public static let breakRange = 1...30

    public init(focusMinutes: Int, breakMinutes: Int) {
        self.focusMinutes = min(max(focusMinutes, Self.focusRange.lowerBound), Self.focusRange.upperBound)
        self.breakMinutes = min(max(breakMinutes, Self.breakRange.lowerBound), Self.breakRange.upperBound)
    }

    public func duration(of phase: PomodoroPhase) -> TimeInterval {
        TimeInterval((phase == .focus ? focusMinutes : breakMinutes) * 60)
    }
}

public enum PomodoroPhase: String, Codable, Equatable, Sendable {
    case focus
    /// The break that follows a focus session.
    case rest
}

/// One phase of a Pomodoro under way. Like the timer, it knows where it is at any moment without ticking.
public struct Pomodoro: Equatable, Sendable {
    public private(set) var phase: PomodoroPhase
    public var countdown: Countdown

    public init(phase: PomodoroPhase, plan: PomodoroPlan, starting date: Date) {
        self.phase = phase
        countdown = Countdown(total: plan.duration(of: phase), starting: date)
    }

    /// What follows when this phase rings: a break after focus, which starts by itself; nothing after a break, so a
    /// Pomodoro never runs on while you are away.
    public func next(plan: PomodoroPlan, at date: Date) -> Pomodoro? {
        phase == .focus ? Pomodoro(phase: .rest, plan: plan, starting: date) : nil
    }
}

/// Focus sessions completed today. It starts again from zero on a new day.
public struct PomodoroTally: Codable, Equatable, Sendable {
    /// The day counted, as "2026-11-16" in the user's calendar.
    public var day: String
    public var count: Int

    public init(day: String = "", count: Int = 0) {
        self.day = day
        self.count = count
    }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func count(on date: Date, calendar: Calendar = .current) -> Int {
        day == Self.key(for: date, calendar: calendar) ? count : 0
    }

    /// Counts a focus session completed at `date`.
    public mutating func add(at date: Date, calendar: Calendar = .current) {
        let today = Self.key(for: date, calendar: calendar)
        count = day == today ? count + 1 : 1
        day = today
    }
}

import Foundation

extension RGBA {
    /// The colour lifted just enough to be read on the black island: a calendar's dark blue or brown stays itself,
    /// a little lighter. Colours already light enough are left as they are.
    public var readableOnBlack: RGBA {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        guard luminance < 0.25 else { return self }
        let lift = 0.25 - luminance
        return RGBA(red: min(red + lift, 1), green: min(green + lift, 1), blue: min(blue + lift, 1), alpha: alpha)
    }
}

/// The countdown to the next meeting in the closed island: it starts a few minutes before an event and says "now"
/// for a moment once it begins. Worked out from the times alone, so the island wakes up only when it changes.
public enum MeetingCountdown {
    public struct Event: Equatable, Sendable {
        public var id: String
        public var start: Date
        public var isAllDay: Bool

        public init(id: String, start: Date, isAllDay: Bool = false) {
            self.id = id
            self.start = start
            self.isAllDay = isAllDay
        }
    }

    /// How long the island says "now" once the event has started.
    public static let startLinger: TimeInterval = 2 * 60
    /// The minutes before an event the countdown may start at, as the settings offer them.
    public static let leadRange = 1...30

    /// The event to count down to: the soonest timed one that starts within `lead` seconds, or started less than
    /// `startLinger` ago. All-day events have no start to count down to.
    public static func current(in events: [Event], now: Date, lead: TimeInterval) -> Event? {
        events
            .filter { !$0.isAllDay && $0.start.timeIntervalSince(now) <= lead && now.timeIntervalSince($0.start) < startLinger }
            .min { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// True once the event has begun: the island says "now" instead of counting.
    public static func hasStarted(_ event: Event, now: Date) -> Bool {
        event.start <= now
    }

    /// The next moment the countdown changes: an event entering its window, the one shown starting, or its "now"
    /// ending. Nil when nothing is ahead.
    public static func nextChange(in events: [Event], now: Date, lead: TimeInterval) -> Date? {
        events.filter { !$0.isAllDay }
            .flatMap { [$0.start.addingTimeInterval(-lead), $0.start, $0.start.addingTimeInterval(startLinger)] }
            .filter { $0 > now }
            .min()
    }
}

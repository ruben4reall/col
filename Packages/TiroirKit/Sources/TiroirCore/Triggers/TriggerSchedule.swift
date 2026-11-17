import Foundation

/// What the sensors must watch for the enabled triggers. Nothing at all when none needs it: Tiroir runs no timer and
/// polls nothing at rest.
public struct TriggerSensorNeeds: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Apps that launch and quit.
    public static let runningApps = TriggerSensorNeeds(rawValue: 1 << 0)
    /// The app in front.
    public static let frontmostApp = TriggerSensorNeeds(rawValue: 1 << 1)
    /// The power source and the battery's charge.
    public static let power = TriggerSensorNeeds(rawValue: 1 << 2)
    /// Displays that are connected or disconnected.
    public static let displays = TriggerSensorNeeds(rawValue: 1 << 3)
    /// The time of day: one timer to the next start or end of a time range.
    public static let clock = TriggerSensorNeeds(rawValue: 1 << 4)
    /// Whether any camera or microphone runs.
    public static let cameraAndMicrophone = TriggerSensorNeeds(rawValue: 1 << 5)
}

/// When triggers need to look again: which sensors, and at what time of day (spec: Triggers).
public enum TriggerSchedule {
    /// The sensors the enabled triggers need.
    public static func needs(of triggers: [Trigger]) -> TriggerSensorNeeds {
        var needs: TriggerSensorNeeds = []
        for trigger in triggers where trigger.isEnabled {
            switch trigger.condition {
            case .appOpen: needs.insert(.runningApps)
            case .appInFront: needs.insert(.frontmostApp)
            case .onBattery, .batteryAtOrBelow: needs.insert(.power)
            case .externalDisplay: needs.insert(.displays)
            case .timeOfDay: needs.insert(.clock)
            case .cameraOrMicrophone: needs.insert(.cameraAndMicrophone)
            }
        }
        return needs
    }

    /// The minutes of the day at which an enabled time range starts or ends.
    public static func boundaries(of triggers: [Trigger]) -> Set<Int> {
        var minutes = Set<Int>()
        for trigger in triggers where trigger.isEnabled {
            guard case .timeOfDay(let from, let to) = trigger.condition.clamped, from != to else { continue }
            minutes.insert(from)
            minutes.insert(to)
        }
        return minutes
    }

    /// The first moment after `now` at which a boundary is reached, for the one timer of time ranges; nil when there
    /// is no boundary. A time skipped by a change to summer time counts as the next moment that exists.
    public static func nextBoundary(after now: Date, boundaries: Set<Int>, calendar: Calendar) -> Date? {
        boundaries
            .compactMap { minute in
                calendar.nextDate(after: now, matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0),
                                  matchingPolicy: .nextTime)
            }
            .min()
    }

    /// The time of day of `date`, in minutes since midnight.
    public static func minutesSinceMidnight(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

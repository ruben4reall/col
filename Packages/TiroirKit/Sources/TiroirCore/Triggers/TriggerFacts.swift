import Foundation

/// What the Mac is doing at one moment, as far as triggers care. The sensors fill in what enabled triggers need; the
/// rest keeps its default and makes no condition hold.
public struct TriggerFacts: Equatable, Sendable {
    /// Bundle identifiers of the apps that run.
    public var runningApps: Set<String>
    /// The bundle identifier of the app in front.
    public var frontmostApp: String?
    public var isOnBattery: Bool
    /// The battery's charge from 0 to 100; nil on a Mac without a battery.
    public var batteryPercent: Int?
    /// A display other than the built-in one is connected.
    public var hasExternalDisplay: Bool
    /// The time of day, from 0 (midnight) to 1439.
    public var minutesSinceMidnight: Int
    /// Any app uses a camera or a microphone.
    public var isCameraOrMicrophoneInUse: Bool

    public init(
        runningApps: Set<String> = [], frontmostApp: String? = nil, isOnBattery: Bool = false, batteryPercent: Int? = nil,
        hasExternalDisplay: Bool = false, minutesSinceMidnight: Int = 0, isCameraOrMicrophoneInUse: Bool = false
    ) {
        self.runningApps = runningApps
        self.frontmostApp = frontmostApp
        self.isOnBattery = isOnBattery
        self.batteryPercent = batteryPercent
        self.hasExternalDisplay = hasExternalDisplay
        self.minutesSinceMidnight = minutesSinceMidnight
        self.isCameraOrMicrophoneInUse = isCameraOrMicrophoneInUse
    }
}

extension TriggerCondition {
    /// Whether the condition holds in these facts.
    public func holds(in facts: TriggerFacts) -> Bool {
        switch self {
        case .appOpen(let bundleID): facts.runningApps.contains(bundleID)
        case .appInFront(let bundleID): facts.frontmostApp == bundleID
        case .onBattery: facts.isOnBattery
        case .batteryAtOrBelow(let percent): facts.batteryPercent.map { $0 <= percent } ?? false
        case .externalDisplay: facts.hasExternalDisplay
        case .timeOfDay(let from, let to): Self.minute(facts.minutesSinceMidnight, isFrom: from, to: to)
        case .cameraOrMicrophone: facts.isCameraOrMicrophoneInUse
        }
    }

    /// From `from` up to, not including, `to`, across midnight when `to` comes first.
    static func minute(_ minute: Int, isFrom from: Int, to: Int) -> Bool {
        if from < to { return minute >= from && minute < to }
        if from > to { return minute >= from || minute < to }
        return false
    }
}

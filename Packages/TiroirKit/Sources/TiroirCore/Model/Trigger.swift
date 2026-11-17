import Foundation

/// What a trigger watches. Each condition is told by an event of the system, never by polling.
public enum TriggerCondition: Codable, Hashable, Sendable {
    /// An app is open, by bundle identifier.
    case appOpen(String)
    /// An app is in front, by bundle identifier.
    case appInFront(String)
    /// The Mac runs on battery.
    case onBattery
    /// The battery is at this percentage or below, plugged in or not.
    case batteryAtOrBelow(Int)
    /// A display other than the built-in one is connected.
    case externalDisplay
    /// The time of day is within a range, in minutes since midnight: from `from` up to, not including, `to`. A range
    /// that ends before it starts crosses midnight; a range that ends where it starts never holds.
    case timeOfDay(from: Int, to: Int)
    /// A camera or a microphone is in use, by any app.
    case cameraOrMicrophone

    /// The kinds of condition, as stored and as offered in Settings.
    public enum Kind: String, CaseIterable, Sendable {
        case appOpen, appInFront, onBattery, batteryAtOrBelow, externalDisplay, timeOfDay, cameraOrMicrophone
    }

    public var kind: Kind {
        switch self {
        case .appOpen: .appOpen
        case .appInFront: .appInFront
        case .onBattery: .onBattery
        case .batteryAtOrBelow: .batteryAtOrBelow
        case .externalDisplay: .externalDisplay
        case .timeOfDay: .timeOfDay
        case .cameraOrMicrophone: .cameraOrMicrophone
        }
    }

    /// The app a condition is about, if any.
    public var app: String? {
        switch self {
        case .appOpen(let bundleID), .appInFront(let bundleID): bundleID
        default: nil
        }
    }

    public static let percentRange = 1...100
    public static let minutesInADay = 24 * 60

    /// Percentages and minutes brought inside their ranges.
    public var clamped: TriggerCondition {
        switch self {
        case .batteryAtOrBelow(let percent): .batteryAtOrBelow(percent.clamped(to: Self.percentRange))
        case .timeOfDay(let from, let to):
            .timeOfDay(from: from.clamped(to: 0...Self.minutesInADay - 1), to: to.clamped(to: 0...Self.minutesInADay - 1))
        default: self
        }
    }

    // A readable encoding: {"kind": "appOpen", "app": "us.zoom.xos"}, {"kind": "timeOfDay", "from": 1080, "to": 480}.
    private enum CodingKeys: String, CodingKey { case kind, app, percent, from, to }

    /// A kind this version does not know (written by a newer Tiroir) or a missing value throws, so that the trigger
    /// holding it is skipped rather than guessed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: name) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown condition \(name)")
        }
        switch kind {
        case .appOpen: self = .appOpen(try container.decode(String.self, forKey: .app))
        case .appInFront: self = .appInFront(try container.decode(String.self, forKey: .app))
        case .onBattery: self = .onBattery
        case .batteryAtOrBelow: self = .batteryAtOrBelow(try container.decode(Int.self, forKey: .percent))
        case .externalDisplay: self = .externalDisplay
        case .timeOfDay: self = .timeOfDay(from: try container.decode(Int.self, forKey: .from), to: try container.decode(Int.self, forKey: .to))
        case .cameraOrMicrophone: self = .cameraOrMicrophone
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        switch self {
        case .appOpen(let bundleID), .appInFront(let bundleID): try container.encode(bundleID, forKey: .app)
        case .batteryAtOrBelow(let percent): try container.encode(percent, forKey: .percent)
        case .timeOfDay(let from, let to):
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case .onBattery, .externalDisplay, .cameraOrMicrophone: break
        }
    }
}

/// What a trigger does while its condition holds. When the condition stops holding, the effect ends.
public enum TriggerAction: Codable, Hashable, Sendable {
    /// Switch to a profile; when the condition ends, the profile active before comes back.
    case switchProfile(UUID)
    /// Show a drawer's icons in the menu bar.
    case showDrawer(UUID)
    /// Show one icon in the menu bar.
    case showIcon(IconID)
    /// Focus: only the clock and Control Center stay.
    case focus

    /// The kinds of action, as stored and as offered in Settings.
    public enum Kind: String, CaseIterable, Sendable {
        case switchProfile, showDrawer, showIcon, focus
    }

    public var kind: Kind {
        switch self {
        case .switchProfile: .switchProfile
        case .showDrawer: .showDrawer
        case .showIcon: .showIcon
        case .focus: .focus
        }
    }

    // {"kind": "showDrawer", "drawer": "…"}, {"kind": "showIcon", "icon": {"bundleID": "…", "key": "…"}}.
    private enum CodingKeys: String, CodingKey { case kind, profile, drawer, icon }

    /// Like conditions, an unknown kind or a missing value throws, and the trigger is skipped.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: name) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown action \(name)")
        }
        switch kind {
        case .switchProfile: self = .switchProfile(try container.decode(UUID.self, forKey: .profile))
        case .showDrawer: self = .showDrawer(try container.decode(UUID.self, forKey: .drawer))
        case .showIcon: self = .showIcon(try container.decode(IconID.self, forKey: .icon))
        case .focus: self = .focus
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        switch self {
        case .switchProfile(let id): try container.encode(id, forKey: .profile)
        case .showDrawer(let id): try container.encode(id, forKey: .drawer)
        case .showIcon(let id): try container.encode(id, forKey: .icon)
        case .focus: break
        }
    }
}

/// While a condition holds, do something; when it stops holding, its effect ends.
public struct Trigger: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var isEnabled: Bool
    public var condition: TriggerCondition
    public var action: TriggerAction

    public init(id: UUID = UUID(), isEnabled: Bool = true, condition: TriggerCondition, action: TriggerAction) {
        self.id = id
        self.isEnabled = isEnabled
        self.condition = condition
        self.action = action
    }

    private enum CodingKeys: String, CodingKey { case id, isEnabled, condition, action }

    /// A trigger needs a condition and an action it understands; without them it is skipped.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        condition = try container.decode(TriggerCondition.self, forKey: .condition)
        action = try container.decode(TriggerAction.self, forKey: .action)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
    }

    public var clamped: Trigger {
        var copy = self
        copy.condition = condition.clamped
        return copy
    }
}

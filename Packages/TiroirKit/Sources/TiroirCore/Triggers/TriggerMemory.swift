import Foundation

/// What comes back when the triggers let go of a profile.
public enum PreviousSetup: Codable, Hashable, Sendable {
    /// The profile that was active.
    case profile(UUID)
    /// No profile was active: the layout and the appearance of that moment.
    case setup(Layout, Appearance)

    private enum CodingKeys: String, CodingKey { case profile, layout, appearance }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(UUID.self, forKey: .profile) {
            self = .profile(id)
        } else {
            let layout = try container.decode(Layout.self, forKey: .layout)
            self = .setup(layout, (try? container.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .standard)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .profile(let id): try container.encode(id, forKey: .profile)
        case .setup(let layout, let appearance):
            try container.encode(layout, forKey: .layout)
            try container.encode(appearance, forKey: .appearance)
        }
    }
}

/// A profile a trigger switched to, and what to bring back when no trigger asks for it any more.
public struct ProfileHold: Codable, Hashable, Sendable {
    /// The trigger whose profile is in place.
    public var trigger: UUID
    /// The profile it switched to.
    public var profile: UUID
    /// What was there before the first trigger switched.
    public var previous: PreviousSetup

    public init(trigger: UUID, profile: UUID, previous: PreviousSetup) {
        self.trigger = trigger
        self.profile = profile
        self.previous = previous
    }
}

/// What the triggers keep between two launches, so that a restart in the middle of a trigger (an update, a Mac that
/// restarts) still brings the right profile back when its condition ends.
public struct TriggerMemory: Codable, Hashable, Sendable {
    /// The profile a trigger put in place, with what to bring back.
    public var hold: ProfileHold?
    /// Triggers the person overruled by switching profiles by hand while they held: they switch nothing more until
    /// their condition ends.
    public var overruled: Set<UUID>

    public init(hold: ProfileHold? = nil, overruled: Set<UUID> = []) {
        self.hold = hold
        self.overruled = overruled
    }

    public static let empty = TriggerMemory()

    private enum CodingKeys: String, CodingKey { case hold, overruled }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hold = try? container.decodeIfPresent(ProfileHold.self, forKey: .hold)
        overruled = Set((try? container.decodeIfPresent([UUID].self, forKey: .overruled)) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(hold, forKey: .hold)
        try container.encode(overruled.sorted { $0.uuidString < $1.uuidString }, forKey: .overruled)
    }
}

import Foundation

/// A colour that crosses from the rules to the drawing without dragging AppKit along.
public struct RGBA: Equatable, Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let green = RGBA(red: 0.2, green: 0.84, blue: 0.4)
    public static let orange = RGBA(red: 1, green: 0.62, blue: 0.04)
    public static let red = RGBA(red: 1, green: 0.27, blue: 0.23)
    public static let blue = RGBA(red: 0.04, green: 0.52, blue: 1)
    public static let purple = RGBA(red: 0.69, green: 0.32, blue: 0.87)
    public static let yellow = RGBA(red: 1, green: 0.84, blue: 0.04)
}

/// What one wing of the compact island shows, beside the camera.
public enum CompactItem: Equatable, Sendable {
    /// An SF Symbol.
    case symbol(String, tint: RGBA = .white)
    /// An image registered with the shell under this key, such as the current artwork.
    case image(key: String)
    /// Bars that dance while `playing`.
    case equalizer(tint: RGBA, playing: Bool)
    case text(String, tint: RGBA = .white)
    /// A ring that fills from 0 to 1.
    case ring(progress: Double, tint: RGBA)
    /// A horizontal gauge from 0 to 1, for volume and brightness.
    case level(Double, tint: RGBA = .white)
    case battery(level: Double, charging: Bool)
    /// A small arc that turns while something works.
    case spinner(tint: RGBA)
    /// A ring that empties until `ends`, animated by the render server rather than by ticks.
    case countdown(ends: Date, total: TimeInterval, tint: RGBA)
    /// The icon of the app behind the activity. `attention` is when the app began to need the user: the icon hops a
    /// few times, as in the Dock, then rests, and hops again only for a later request.
    case appIcon(AppIcon, attention: Date? = nil)
}

public struct CompactPresentation: Equatable, Sendable {
    public var leading: CompactItem?
    public var trailing: CompactItem?

    public init(leading: CompactItem? = nil, trailing: CompactItem? = nil) {
        self.leading = leading
        self.trailing = trailing
    }

    /// What the wings can show. A single wing carries one item: the trailing one, which holds the value (level,
    /// countdown, equalizer), or the leading one when there is no value.
    public func fitted(to wings: Wings) -> CompactPresentation? {
        if wings.isEmpty { return nil }
        guard wings.isOneSided else { return self }
        let item = trailing ?? leading
        return wings.leading > 0 ? CompactPresentation(leading: item) : CompactPresentation(trailing: item)
    }
}

/// Which activity wins the notch when several want it.
public enum ActivityPriority: Int, Comparable, Sendable {
    /// Always-on context: the music playing.
    case ambient
    /// Something running: a timer, a build, an agent at work.
    case standard
    /// Something that needs the user: an agent waiting for approval, a low battery.
    case alert
    /// A brief acknowledgement: volume, brightness, a charger plugged in.
    case transient

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct Activity: Equatable, Sendable, Identifiable {
    public var id: String
    public var priority: ActivityPriority
    public var compact: CompactPresentation
    /// When the activity leaves by itself; nil keeps it until it is removed.
    public var expires: Date?
    public var updated: Date

    public init(id: String, priority: ActivityPriority, compact: CompactPresentation, expires: Date? = nil, updated: Date) {
        self.id = id
        self.priority = priority
        self.compact = compact
        self.expires = expires
        self.updated = updated
    }
}

/// Where an activity that is not urgent comes from. The user orders these sources to choose what the closed island
/// shows first when several things run at once.
public enum ActivitySource: String, CaseIterable, Codable, Sendable {
    case privacy, agents, timers, downloads, scripts, music, keepAwake

    /// The source of an activity, from its identifier; nil for one that belongs to none (brief displays, alerts).
    public init?(activityID id: String) {
        if id == "privacy" { self = .privacy }
        else if id == "agents" { self = .agents }
        else if id == "timer" { self = .timers }
        else if id.hasPrefix("download.") { self = .downloads }
        else if id.hasPrefix("api.") { self = .scripts }
        else if id == "media" || id.hasPrefix("media.") { self = .music }
        else if id == "awake" { self = .keepAwake }
        else { return nil }
    }

    /// The order a source list is read in: the user's, with any source it does not mention added at the end.
    public static func completed(_ ranking: [ActivitySource]) -> [ActivitySource] {
        var order: [ActivitySource] = []
        for source in ranking + allCases where !order.contains(source) { order.append(source) }
        return order
    }
}

/// Every live activity, and the rule that picks the one the notch shows. Alerts and brief displays come first, the
/// highest priority then the most recent. Then the sources in the user's order; within a source, the highest
/// priority, then the most recent.
public struct ActivityBoard: Sendable {
    public private(set) var activities: [String: Activity] = [:]
    /// The sources from first to last. By default the ones that need an eye before the ones that keep company.
    public var ranking: [ActivitySource] = ActivitySource.allCases {
        didSet { ranking = ActivitySource.completed(ranking) }
    }

    public init() {}

    public mutating func upsert(_ activity: Activity) {
        activities[activity.id] = activity
    }

    public mutating func remove(_ id: String) {
        activities[id] = nil
    }

    /// Drops the activities whose time is up. Returns true when something left.
    @discardableResult
    public mutating func prune(now: Date) -> Bool {
        let expired = activities.values.filter { ($0.expires ?? .distantFuture) <= now }.map(\.id)
        expired.forEach { activities[$0] = nil }
        return !expired.isEmpty
    }

    public func current(now: Date) -> Activity? {
        let live = activities.values.filter { ($0.expires ?? .distantFuture) > now }
        if let urgent = live.filter({ $0.priority >= .alert }).max(by: { ($0.priority, $0.updated, $1.id) < ($1.priority, $1.updated, $0.id) }) {
            return urgent
        }
        func rank(_ activity: Activity) -> Int {
            ActivitySource(activityID: activity.id).flatMap { ranking.firstIndex(of: $0) } ?? ranking.count
        }
        return live.min { lhs, rhs in
            let (left, right) = (rank(lhs), rank(rhs))
            if left != right { return left < right }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.updated != rhs.updated { return lhs.updated > rhs.updated }
            return lhs.id < rhs.id
        }
    }

    /// The next moment an activity expires, to wake up exactly then instead of polling.
    public func nextExpiry(after now: Date) -> Date? {
        activities.values.compactMap(\.expires).filter { $0 > now }.min()
    }
}

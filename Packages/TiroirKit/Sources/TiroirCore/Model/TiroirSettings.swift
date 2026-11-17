import Foundation

/// How drawers and hidden icons behave (spec 6.3, Behavior).
public struct Behavior: Codable, Hashable, Sendable {
    /// Where Show Every Icon shows them: in the menu bar itself, or in the All drawer's panel, where every icon fits
    /// even beside a notch.
    public enum RevealPlace: String, Codable, Sendable, CaseIterable {
        case menuBar, allDrawer
    }

    /// Open a drawer when the pointer rests on its mark.
    public var opensOnHover: Bool
    /// How long the pointer rests before a drawer opens, in seconds.
    public var hoverDelay: Double
    /// How long an icon opened from a drawer stays in the menu bar after its menu closes, in seconds.
    public var rehideDelay: Double
    /// Option-click on Tiroir's icon shows every icon, and hides them again.
    public var showsEverythingWithOption: Bool
    /// Show Tiroir's own icon (the All drawer). Without it, Settings open from a right-click on any drawer.
    public var showsTiroirIcon: Bool
    /// Keep Tiroir's icon and drawers together at the right end of the menu bar, next to Control Center. Off, they
    /// stay wherever the person Command-drags them.
    public var keepsItemsAtRightEnd: Bool
    /// Show every icon when the pointer rests on an empty part of the menu bar.
    public var revealsOnHover: Bool
    /// Show every icon after a click on an empty part of the menu bar.
    public var revealsOnClick: Bool
    /// Show every icon after a scroll or a swipe in the menu bar.
    public var revealsOnScroll: Bool
    public var revealPlace: RevealPlace
    /// Hide the icons again once the pointer has left the menu bar for `hideAgainDelay` seconds with no menu open.
    public var hidesAgainAutomatically: Bool
    public var hideAgainDelay: Double
    /// Move the icons that stop fitting beside the notch into a drawer, as soon as it happens.
    public var movesOverflowAutomatically: Bool

    public init(opensOnHover: Bool = false, hoverDelay: Double = 0.25, rehideDelay: Double = 0.5,
                showsEverythingWithOption: Bool = true, showsTiroirIcon: Bool = true, keepsItemsAtRightEnd: Bool = true,
                revealsOnHover: Bool = false,
                revealsOnClick: Bool = false, revealsOnScroll: Bool = false, revealPlace: RevealPlace = .menuBar,
                hidesAgainAutomatically: Bool = true, hideAgainDelay: Double = 5, movesOverflowAutomatically: Bool = false) {
        self.opensOnHover = opensOnHover
        self.hoverDelay = hoverDelay
        self.rehideDelay = rehideDelay
        self.showsEverythingWithOption = showsEverythingWithOption
        self.showsTiroirIcon = showsTiroirIcon
        self.keepsItemsAtRightEnd = keepsItemsAtRightEnd
        self.revealsOnHover = revealsOnHover
        self.revealsOnClick = revealsOnClick
        self.revealsOnScroll = revealsOnScroll
        self.revealPlace = revealPlace
        self.hidesAgainAutomatically = hidesAgainAutomatically
        self.hideAgainDelay = hideAgainDelay
        self.movesOverflowAutomatically = movesOverflowAutomatically
    }

    public static let hoverDelayRange: ClosedRange<Double> = 0.1...1.0
    public static let rehideDelayRange: ClosedRange<Double> = 0...10
    public static let hideAgainDelayRange: ClosedRange<Double> = 1...30

    /// Whether anything shows every icon besides Tiroir's own icon and menu.
    public var revealsFromTheMenuBar: Bool { revealsOnHover || revealsOnClick || revealsOnScroll }

    public var clamped: Behavior {
        var copy = self
        copy.hoverDelay = hoverDelay.clamped(to: Self.hoverDelayRange)
        copy.rehideDelay = rehideDelay.clamped(to: Self.rehideDelayRange)
        copy.hideAgainDelay = hideAgainDelay.clamped(to: Self.hideAgainDelayRange)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case opensOnHover, hoverDelay, rehideDelay, showsEverythingWithOption, showsTiroirIcon, keepsItemsAtRightEnd, revealsOnHover
        case revealsOnClick
        case revealsOnScroll, revealPlace, hidesAgainAutomatically, hideAgainDelay, movesOverflowAutomatically
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Behavior()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        opensOnHover = value(.opensOnHover, standard.opensOnHover)
        hoverDelay = value(.hoverDelay, standard.hoverDelay)
        rehideDelay = value(.rehideDelay, standard.rehideDelay)
        showsEverythingWithOption = value(.showsEverythingWithOption, standard.showsEverythingWithOption)
        showsTiroirIcon = value(.showsTiroirIcon, standard.showsTiroirIcon)
        keepsItemsAtRightEnd = value(.keepsItemsAtRightEnd, standard.keepsItemsAtRightEnd)
        revealsOnHover = value(.revealsOnHover, standard.revealsOnHover)
        revealsOnClick = value(.revealsOnClick, standard.revealsOnClick)
        revealsOnScroll = value(.revealsOnScroll, standard.revealsOnScroll)
        revealPlace = value(.revealPlace, standard.revealPlace)
        hidesAgainAutomatically = value(.hidesAgainAutomatically, standard.hidesAgainAutomatically)
        hideAgainDelay = value(.hideAgainDelay, standard.hideAgainDelay)
        movesOverflowAutomatically = value(.movesOverflowAutomatically, standard.movesOverflowAutomatically)
    }
}

/// A shortcut that opens one icon's menu, wherever the icon lives.
public struct IconShortcut: Codable, Hashable, Sendable {
    public var icon: IconID
    public var shortcut: Shortcut

    public init(icon: IconID, shortcut: Shortcut) {
        self.icon = icon
        self.shortcut = shortcut
    }
}

/// The global shortcuts. Each one can be off.
public struct Shortcuts: Codable, Hashable, Sendable {
    public var search: Shortcut?
    public var allDrawer: Shortcut?
    public var focus: Shortcut?
    public var showEverything: Shortcut?
    /// At most one shortcut per icon.
    public var icons: [IconShortcut]

    public init(search: Shortcut? = .defaultSearch, allDrawer: Shortcut? = nil, focus: Shortcut? = .defaultFocus,
                showEverything: Shortcut? = nil, icons: [IconShortcut] = []) {
        self.search = search
        self.allDrawer = allDrawer
        self.focus = focus
        self.showEverything = showEverything
        self.icons = icons
    }

    /// The shortcut that opens this icon, if any.
    public func shortcut(for icon: IconID) -> Shortcut? {
        icons.first { $0.icon == icon }?.shortcut
    }

    /// Gives an icon a shortcut, or takes it away with nil.
    public mutating func setShortcut(_ shortcut: Shortcut?, for icon: IconID) {
        icons.removeAll { $0.icon == icon }
        if let shortcut { icons.append(IconShortcut(icon: icon, shortcut: shortcut)) }
    }

    private enum CodingKeys: String, CodingKey { case search, allDrawer, focus, showEverything, icons }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A key that is present but null means the person turned the shortcut off.
        search = container.contains(.search) ? try? container.decodeIfPresent(Shortcut.self, forKey: .search) : .defaultSearch
        allDrawer = try? container.decodeIfPresent(Shortcut.self, forKey: .allDrawer)
        focus = container.contains(.focus) ? try? container.decodeIfPresent(Shortcut.self, forKey: .focus) : .defaultFocus
        showEverything = try? container.decodeIfPresent(Shortcut.self, forKey: .showEverything)
        // One unreadable entry costs that entry only; a second shortcut for the same icon is dropped.
        let entries = (try? container.decodeIfPresent([FailableIconShortcut].self, forKey: .icons)) ?? []
        var seen: Set<IconID> = []
        icons = entries.compactMap(\.value).filter { seen.insert($0.icon).inserted }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(search, forKey: .search)
        try container.encode(allDrawer, forKey: .allDrawer)
        try container.encode(focus, forKey: .focus)
        try container.encode(showEverything, forKey: .showEverything)
        try container.encode(icons, forKey: .icons)
    }

    private struct FailableIconShortcut: Decodable {
        let value: IconShortcut?
        init(from decoder: Decoder) throws { value = try? IconShortcut(from: decoder) }
    }
}

/// How Smart Sort groups icons.
public enum SortStrategy: String, Codable, Sendable, CaseIterable {
    /// One drawer per kind of app: files and cloud, security, messages…
    case purpose
    /// One drawer per developer: Google, Proton, Microsoft…
    case developer
    /// Every icon in one drawer.
    case justOne
}

/// Everything Tiroir remembers, stored as one JSON value (spec 8).
public struct TiroirSettings: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var layout: Layout
    public var appearance: Appearance
    public var behavior: Behavior
    public var shortcuts: Shortcuts
    /// The person's own answer to "what is this app for", by bundle identifier; it outlives the app.
    public var userCategories: [String: CategoryID]
    /// Icons Smart Sort must leave in the menu bar.
    public var pinned: Set<IconID>
    public var sortStrategy: SortStrategy
    public var hasCompletedWelcome: Bool
    /// Saved setups of the menu bar, in the order Settings and Tiroir's menu list them.
    public var profiles: [Profile]
    /// The profile in use, which follows every change of the layout and the appearance; nil when none is.
    public var activeProfile: UUID?
    public var triggers: [Trigger]
    /// What the triggers keep between two launches.
    public var triggerMemory: TriggerMemory

    public init(
        layout: Layout = .empty, appearance: Appearance = .standard, behavior: Behavior = Behavior(),
        shortcuts: Shortcuts = Shortcuts(), userCategories: [String: CategoryID] = [:], pinned: Set<IconID> = [],
        sortStrategy: SortStrategy = .purpose, hasCompletedWelcome: Bool = false, profiles: [Profile] = [],
        activeProfile: UUID? = nil, triggers: [Trigger] = [], triggerMemory: TriggerMemory = .empty
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.layout = layout
        self.appearance = appearance
        self.behavior = behavior
        self.shortcuts = shortcuts
        self.userCategories = userCategories
        self.pinned = pinned
        self.sortStrategy = sortStrategy
        self.hasCompletedWelcome = hasCompletedWelcome
        self.profiles = profiles
        self.activeProfile = activeProfile
        self.triggers = triggers
        self.triggerMemory = triggerMemory
    }

    public static let defaults = TiroirSettings()

    /// Every value brought inside its range, every drawer and profile name and mark cleaned, one profile per identity,
    /// and no active profile that does not exist.
    public var clamped: TiroirSettings {
        var copy = self
        copy.appearance = appearance.clamped
        copy.behavior = behavior.clamped
        copy.layout.drawers = layout.drawers.map(\.clamped)
        var seen = Set<UUID>()
        copy.profiles = profiles.filter { seen.insert($0.id).inserted }.map(\.clamped)
        if let active = activeProfile, !seen.contains(active) { copy.activeProfile = nil }
        copy.triggers = triggers.map(\.clamped)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, layout, appearance, behavior, shortcuts, userCategories, pinned, sortStrategy, hasCompletedWelcome
        case profiles, activeProfile, triggers, triggerMemory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = TiroirSettings()
        schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        layout = (try? container.decodeIfPresent(Layout.self, forKey: .layout)) ?? standard.layout
        appearance = (try? container.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? standard.appearance
        behavior = (try? container.decodeIfPresent(Behavior.self, forKey: .behavior)) ?? standard.behavior
        shortcuts = (try? container.decodeIfPresent(Shortcuts.self, forKey: .shortcuts)) ?? standard.shortcuts
        let rawCategories = (try? container.decodeIfPresent([String: String].self, forKey: .userCategories)) ?? [:]
        userCategories = rawCategories.compactMapValues(CategoryID.init(rawValue:))
        pinned = (try? container.decodeIfPresent(Set<IconID>.self, forKey: .pinned)) ?? []
        sortStrategy = (try? container.decodeIfPresent(SortStrategy.self, forKey: .sortStrategy)) ?? standard.sortStrategy
        hasCompletedWelcome = (try? container.decodeIfPresent(Bool.self, forKey: .hasCompletedWelcome)) ?? false
        // A profile or a trigger that cannot be read is skipped, never the whole settings.
        profiles = ((try? container.decodeIfPresent([Failable<Profile>].self, forKey: .profiles)) ?? []).compactMap(\.value)
        activeProfile = try? container.decodeIfPresent(UUID.self, forKey: .activeProfile)
        triggers = ((try? container.decodeIfPresent([Failable<Trigger>].self, forKey: .triggers)) ?? []).compactMap(\.value)
        triggerMemory = (try? container.decodeIfPresent(TriggerMemory.self, forKey: .triggerMemory)) ?? .empty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(layout, forKey: .layout)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(behavior, forKey: .behavior)
        try container.encode(shortcuts, forKey: .shortcuts)
        try container.encode(userCategories.mapValues(\.rawValue), forKey: .userCategories)
        try container.encode(pinned.sorted(), forKey: .pinned)
        try container.encode(sortStrategy, forKey: .sortStrategy)
        try container.encode(hasCompletedWelcome, forKey: .hasCompletedWelcome)
        try container.encode(profiles, forKey: .profiles)
        try container.encodeIfPresent(activeProfile, forKey: .activeProfile)
        try container.encode(triggers, forKey: .triggers)
        try container.encode(triggerMemory, forKey: .triggerMemory)
    }
}

/// Decodes an element of a list, or nothing when that element cannot be read, so that the rest of the list survives.
struct Failable<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

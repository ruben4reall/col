import Foundation
import IsletCore

/// How fast the island moves.
enum MotionStyle: String, CaseIterable, Identifiable {
    case snappy, standard, relaxed
    var id: String { rawValue }
    /// Multiplies every perceptual duration.
    var factor: Double {
        switch self {
        case .snappy: 0.78
        case .standard: 1
        case .relaxed: 1.3
        }
    }
}

/// How the open island meets the desktop, as macOS lets you choose for Liquid Glass.
enum IslandGlass: String, CaseIterable, Identifiable {
    /// Clear glass that bends what is behind it like a thick lens, and catches the light at its edges.
    case liquid
    /// A light blur of what is behind the island, a little dimmed: the most see-through.
    case transparent
    /// Apple's Liquid Glass, frosted.
    case tinted
    /// The all-black island.
    case off
    var id: String { rawValue }
}

/// User settings, stored in the standard defaults.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    /// Posted after any setting changes.
    static let didChange = Notification.Name("IsletPreferencesDidChange")

    private static func bool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    /// Replace the volume and brightness displays of macOS with Islet's. Needs the Accessibility permission.
    static var replacesSystemHUD: Bool {
        get { bool("replacesSystemHUD", default: true) }
        set { defaults.set(newValue, forKey: "replacesSystemHUD"); changed() }
    }

    static var showsMicrophoneAndCamera: Bool {
        get { bool("showsMicrophoneAndCamera", default: true) }
        set { defaults.set(newValue, forKey: "showsMicrophoneAndCamera"); changed() }
    }

    static var showsBattery: Bool {
        get { bool("showsBattery", default: true) }
        set { defaults.set(newValue, forKey: "showsBattery"); changed() }
    }

    static var showsAudioDevices: Bool {
        get { bool("showsAudioDevices", default: true) }
        set { defaults.set(newValue, forKey: "showsAudioDevices"); changed() }
    }

    /// Keep recent text copies, in memory only.
    static var keepsClipboardHistory: Bool {
        get { bool("keepsClipboardHistory", default: true) }
        set { defaults.set(newValue, forKey: "keepsClipboardHistory"); changed() }
    }

    /// Keep the island, and widgets under the clock, on the Lock Screen. Experimental: it relies on private APIs.
    static var showsOnLockScreen: Bool {
        get { bool("showsOnLockScreen", default: false) }
        set { defaults.set(newValue, forKey: "showsOnLockScreen"); changed() }
    }

    static var opensOnHover: Bool {
        get { bool("opensOnHover", default: true) }
        set { defaults.set(newValue, forKey: "opensOnHover"); changed() }
    }

    private static func changed() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: Island

    static var islandSize: IslandSize {
        get { IslandSize(rawValue: defaults.string(forKey: "islandSize") ?? "") ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: "islandSize"); changed() }
    }

    /// The open island melts from black into glass toward its lower edge (macOS 26 and later).
    static var islandGlass: IslandGlass {
        get { IslandGlass(rawValue: defaults.string(forKey: "islandGlass") ?? "") ?? .liquid }
        set { defaults.set(newValue.rawValue, forKey: "islandGlass"); changed() }
    }

    static var motionStyle: MotionStyle {
        get { MotionStyle(rawValue: defaults.string(forKey: "motionStyle") ?? "") ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: "motionStyle"); changed() }
    }

    /// Seconds the pointer rests on the notch before the island opens by itself.
    static var hoverDelay: Double {
        get { defaults.object(forKey: "hoverDelay") == nil ? 0.18 : min(max(defaults.double(forKey: "hoverDelay"), 0), 1.5) }
        set { defaults.set(newValue, forKey: "hoverDelay"); changed() }
    }

    /// Which running things the closed island shows first, when several run at once. Alerts and brief displays always
    /// come before them.
    static var activityRanking: [ActivitySource] {
        get {
            let saved = (defaults.stringArray(forKey: "activityRanking") ?? []).compactMap(ActivitySource.init(rawValue:))
            return ActivitySource.completed(saved)
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: "activityRanking"); changed() }
    }

    /// The pages of the open island, in tab order. Islet 1 kept a list of its optional pages instead: that list becomes
    /// the first deck, so an update keeps the island as it was.
    static var pageDeck: PageDeck {
        get {
            if let data = defaults.data(forKey: "pageDeck"), let deck = try? JSONDecoder().decode(PageDeck.self, from: data) {
                return deck.validated()
            }
            if let legacy = defaults.stringArray(forKey: "enabledPages") { return PageDeck.migrating(enabledPages: legacy) }
            return .standard
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue.validated()), forKey: "pageDeck")
            changed()
        }
    }

    /// Keep the island out of screenshots and screen recordings.
    static var hiddenFromScreenCapture: Bool {
        get { bool("hiddenFromScreenCapture", default: false) }
        set { defaults.set(newValue, forKey: "hiddenFromScreenCapture"); changed() }
    }

    static var showsMediaActivity: Bool {
        get { bool("showsMediaActivity", default: true) }
        set { defaults.set(newValue, forKey: "showsMediaActivity"); changed() }
    }

    static var showsTrackChanges: Bool {
        get { bool("showsTrackChanges", default: true) }
        set { defaults.set(newValue, forKey: "showsTrackChanges"); changed() }
    }

    static var showsAgents: Bool {
        get { bool("showsAgents", default: true) }
        set { defaults.set(newValue, forKey: "showsAgents"); changed() }
    }

    /// A card with the battery when headphones connect.
    static var showsDeviceCard: Bool {
        get { bool("showsDeviceCard", default: true) }
        set { defaults.set(newValue, forKey: "showsDeviceCard"); changed() }
    }

    /// Step aside while an app is in full screen; brief displays such as the volume still show.
    static var hidesInFullScreen: Bool {
        get { bool("hidesInFullScreen", default: true) }
        set { defaults.set(newValue, forKey: "hidesInFullScreen"); changed() }
    }

    /// "notch": the screen with the notch, or the built-in one; "main": the screen with the active window.
    static var displayChoice: String {
        get { defaults.string(forKey: "displayChoice") ?? "notch" }
        set { defaults.set(newValue, forKey: "displayChoice"); changed() }
    }

    /// Follow downloads in progress. Off by default: reading Downloads asks for a permission.
    static var watchesDownloads: Bool {
        get { bool("watchesDownloads", default: false) }
        set { defaults.set(newValue, forKey: "watchesDownloads"); changed() }
    }

    /// Control, Option, Command and I open and close the island.
    static var hotKeyEnabled: Bool {
        get { bool("hotKeyEnabled", default: true) }
        set { defaults.set(newValue, forKey: "hotKeyEnabled"); changed() }
    }
}

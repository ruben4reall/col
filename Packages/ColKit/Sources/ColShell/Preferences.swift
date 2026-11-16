import Foundation
import ColCore

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
    static let didChange = Notification.Name("ColPreferencesDidChange")

    private static func bool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    /// Replace the volume and brightness displays of macOS with Col's. Needs the Accessibility permission.
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

    /// The model servers the user added, on this Mac or another machine. Their tokens live in the Keychain.
    static var aiServers: [ModelServer] {
        get { defaults.data(forKey: "aiServers").flatMap { try? JSONDecoder().decode([ModelServer].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "aiServers"); changed() }
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

    /// The pages of the open island, in tab order. Islet 1 kept a list of its optional pages instead: the first launch
    /// of 2.0 makes it the first deck, with the prompter and the AI apps added (NameChange), so an update keeps the
    /// island as it was. Until a deck is saved, the list reads the same way.
    static var pageDeck: PageDeck {
        get {
            if let data = defaults.data(forKey: "pageDeck"), let deck = try? JSONDecoder().decode(PageDeck.self, from: data) {
                return deck.validated()
            }
            if let legacy = defaults.stringArray(forKey: "enabledPages") {
                return PageDeck.migrating(enabledPages: legacy)
            }
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

    /// Synced lyrics for what plays, looked up on LRCLIB.
    static var showsLyrics: Bool {
        get { bool("showsLyrics", default: true) }
        set { defaults.set(newValue, forKey: "showsLyrics"); changed() }
    }

    /// The line being sung, in the closed island's right wing.
    static var showsLyricsInClosedIsland: Bool {
        get { bool("showsLyricsInClosedIsland", default: false) }
        set { defaults.set(newValue, forKey: "showsLyricsInClosedIsland"); changed() }
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

    /// How the island looks on a screen without a notch: a pill in the menu bar by default, as the iPhone's island
    /// sits in its status bar.
    static var floatingStyle: FloatingStyle {
        get { FloatingStyle(rawValue: defaults.string(forKey: "floatingStyle") ?? "") ?? .pill }
        set { defaults.set(newValue.rawValue, forKey: "floatingStyle"); changed() }
    }

    /// Under a notch, the island hangs from it, or floats below the menu bar (`.below`), for a Mac whose notch area
    /// is taken by something else.
    static var notchStyle: FloatingStyle {
        get { defaults.string(forKey: "notchStyle") == FloatingStyle.below.rawValue ? .below : .notch }
        set { defaults.set(newValue == .below ? FloatingStyle.below.rawValue : FloatingStyle.notch.rawValue, forKey: "notchStyle"); changed() }
    }

    /// Without a notch to hide behind, the resting island still shows: a small black pill, or Col's notch. Off, it
    /// appears only when something happens.
    static var showsIslandAtRest: Bool {
        get { bool("showsIslandAtRest", default: true) }
        set { defaults.set(newValue, forKey: "showsIslandAtRest"); changed() }
    }

    /// How far the closed island may reach on each side of the camera, at most: it never covers a menu or an icon
    /// anyway. 96, 132 (the default) or 160 points.
    static var wingLimit: CGFloat {
        get { defaults.object(forKey: "wingLimit") == nil ? IslandLayout.standardWing : CGFloat(defaults.double(forKey: "wingLimit")) }
        set { defaults.set(Double(newValue), forKey: "wingLimit"); changed() }
    }

    /// Apps in front of which the island steps aside, as in full screen: brief displays and alerts still show.
    static var hiddenInApps: [String] {
        get { defaults.stringArray(forKey: "hiddenInApps") ?? [] }
        set { defaults.set(newValue, forKey: "hiddenInApps"); changed() }
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

    // MARK: Your Mac at a glance

    /// The weather, from Open-Meteo. Off by default: it goes online, and asks for the location unless a city is typed.
    static var showsWeather: Bool {
        get { bool("showsWeather", default: false) }
        set { defaults.set(newValue, forKey: "showsWeather"); changed() }
    }

    /// The city typed in the settings; nil follows the Mac's location.
    static var weatherPlace: WeatherPlace? {
        get { defaults.data(forKey: "weatherPlace").flatMap { try? JSONDecoder().decode(WeatherPlace.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "weatherPlace"); changed() }
    }

    /// A brief display when a Focus turns on or off, and a sign on the Live page while one is on. Asks for Focus status.
    static var showsFocus: Bool {
        get { bool("showsFocus", default: false) }
        set { defaults.set(newValue, forKey: "showsFocus"); changed() }
    }

    /// The keyboard backlight keys show their level in the notch, as volume and brightness do.
    static var showsKeyboardBacklight: Bool {
        get { bool("showsKeyboardBacklight", default: true) }
        set { defaults.set(newValue, forKey: "showsKeyboardBacklight"); changed() }
    }

    /// Caps Lock turning on or off shows in the notch. Off by default: it watches the modifier keys.
    static var showsCapsLock: Bool {
        get { bool("showsCapsLock", default: false) }
        set { defaults.set(newValue, forKey: "showsCapsLock"); changed() }
    }

    /// A button mutes the microphone from the island, and the island turns red while it is muted.
    static var mutesMicrophone: Bool {
        get { bool("mutesMicrophone", default: true) }
        set { defaults.set(newValue, forKey: "mutesMicrophone"); changed() }
    }

    /// Control, Option, Command and M mute or unmute the microphone.
    static var microphoneHotKeyEnabled: Bool {
        get { bool("microphoneHotKeyEnabled", default: true) }
        set { defaults.set(newValue, forKey: "microphoneHotKeyEnabled"); changed() }
    }

    /// A countdown in the closed island before the next event of the calendar.
    static var showsNextMeeting: Bool {
        get { bool("showsNextMeeting", default: true) }
        set { defaults.set(newValue, forKey: "showsNextMeeting"); changed() }
    }

    /// How many minutes before an event its countdown starts.
    static var meetingLeadMinutes: Int {
        get {
            let saved = defaults.integer(forKey: "meetingLeadMinutes")
            return saved == 0 ? 5 : min(max(saved, MeetingCountdown.leadRange.lowerBound), MeetingCountdown.leadRange.upperBound)
        }
        set { defaults.set(newValue, forKey: "meetingLeadMinutes"); changed() }
    }

    /// The battery of Bluetooth mice, keyboards and trackpads, and a word when one runs low.
    static var showsAccessoryBatteries: Bool {
        get { bool("showsAccessoryBatteries", default: true) }
        set { defaults.set(newValue, forKey: "showsAccessoryBatteries"); changed() }
    }

    /// Pomodoro in the Tools page and as a widget.
    static var showsPomodoro: Bool {
        get { bool("showsPomodoro", default: true) }
        set { defaults.set(newValue, forKey: "showsPomodoro"); changed() }
    }

    static var pomodoroPlan: PomodoroPlan {
        get { defaults.data(forKey: "pomodoroPlan").flatMap { try? JSONDecoder().decode(PomodoroPlan.self, from: $0) } ?? .standard }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "pomodoroPlan"); changed() }
    }

    /// Convert, resize, compress and read the text of files on the shelf, from their menu.
    static var shelfTools: Bool {
        get { bool("shelfTools", default: true) }
        set { defaults.set(newValue, forKey: "shelfTools"); changed() }
    }

    /// A search field above the recent copies.
    static var searchesClipboard: Bool {
        get { bool("searchesClipboard", default: true) }
        set { defaults.set(newValue, forKey: "searchesClipboard"); changed() }
    }

    /// The graphics processor's load on the System page.
    static var showsGPU: Bool {
        get { bool("showsGPU", default: true) }
        set { defaults.set(newValue, forKey: "showsGPU"); changed() }
    }
}

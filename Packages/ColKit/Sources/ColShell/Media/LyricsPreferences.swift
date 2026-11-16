import Foundation
import ColCore

/// The settings of the lyrics outside the island, and of the bars that follow the sound. Kept apart from the others,
/// in the same defaults, and posting the same notification when they change.
extension Preferences {
    private static func flag(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.bool(forKey: key)
    }

    private static func store(_ value: Any?, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// The lyrics, large, on the Lock Screen while music plays. Needs the Lock Screen feature, which relies on private
    /// macOS functions.
    static var showsLyricsOnLockScreen: Bool {
        get { flag("showsLyricsOnLockScreen", default: false) }
        set { store(newValue, "showsLyricsOnLockScreen") }
    }

    /// The line being sung on the desktop, above the wallpaper and below every window.
    static var showsLyricsOnDesktop: Bool {
        get { flag("showsLyricsOnDesktop", default: false) }
        set { store(newValue, "showsLyricsOnDesktop") }
    }

    static var desktopLyricsPosition: DesktopLyricsPosition {
        get { DesktopLyricsPosition(rawValue: UserDefaults.standard.string(forKey: "desktopLyricsPosition") ?? "") ?? .lowerCenter }
        set { store(newValue.rawValue, "desktopLyricsPosition") }
    }

    static var desktopLyricsSize: DesktopLyricsSize {
        get { DesktopLyricsSize(rawValue: UserDefaults.standard.string(forKey: "desktopLyricsSize") ?? "") ?? .medium }
        set { store(newValue.rawValue, "desktopLyricsSize") }
    }

    /// The bars beside the camera, and a spectrum in the player, move with the sound itself. Asks to record system
    /// audio, which is analysed on the Mac and never kept.
    static var barsFollowSound: Bool {
        get { flag("barsFollowSound", default: false) }
        set { store(newValue, "barsFollowSound") }
    }
}

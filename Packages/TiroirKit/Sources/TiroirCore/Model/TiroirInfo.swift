import Foundation

/// Tiroir, the app the drawers come from. Its identifier also names the drawers' own items when the room beside the
/// notch is counted: no other app's icon carries it.
public enum TiroirInfo {
    public static let bundleIdentifier = "ch.rubencatalao.tiroir"
    /// The standalone app, under its names past and present (Tansu before 1.1). While one runs, Col leaves the menu
    /// bar to it: two apps arranging the same icons would undo each other's work.
    public static let standaloneBundleIdentifiers: Set<String> = [bundleIdentifier, "ch.rubencatalao.tansu"]
    /// Where the standalone app keeps its settings (UserDefaults domain, key `settings`), read once by Col so its drawers
    /// start where Tiroir's were.
    public static let settingsKey = "settings"
}

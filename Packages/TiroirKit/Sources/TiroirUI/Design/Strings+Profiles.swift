import Foundation
import TiroirCore

/// The words of profiles: Settings, Profiles and the Profiles menu of Tiroir's icon.
extension Strings {
    // MARK: Profiles pane

    public static let profiles = String(localized: "Profiles", bundle: .module)
    public static let profilesSubtitle = String(localized: "A profile keeps a whole setup of the menu bar: its drawers, where each icon goes, and the appearance.", bundle: .module)
    public static let noProfilesYet = String(localized: "No profiles yet. Save your current setup to come back to it in one click, from Tiroir's menu or a shortcut.", bundle: .module)
    public static let saveCurrentAsProfile = String(localized: "Save Current Setup as Profile", bundle: .module)
    public static let activeProfileBadge = String(localized: "Active", bundle: .module)
    public static let switchButton = String(localized: "Switch", bundle: .module)
    public static let renameMenuItem = String(localized: "Rename…", bundle: .module)
    public static let duplicate = String(localized: "Duplicate", bundle: .module)
    public static let moreActions = String(localized: "More", bundle: .module)
    public static let dragToReorder = String(localized: "Drag to change the order.", bundle: .module)
    public static let moveUp = String(localized: "Move Up", bundle: .module)
    public static let moveDown = String(localized: "Move Down", bundle: .module)

    public static func drawerCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 drawer", bundle: .module)
            : String(format: String(localized: "%lld drawers", bundle: .module), count)
    }

    // MARK: Naming

    public static let newProfileTitle = String(localized: "New Profile", bundle: .module)
    public static let newProfileMessage = String(localized: "It starts as the setup you have now, and follows your changes while it is active.", bundle: .module)
    public static let renameProfileTitle = String(localized: "Rename Profile", bundle: .module)
    public static let save = String(localized: "Save", bundle: .module)
    public static let rename = String(localized: "Rename", bundle: .module)
    public static let untitledProfile = String(localized: "Untitled Profile", bundle: .module)

    /// "Profile 2": the name a new profile is offered.
    public static func numberedProfileName(_ number: Int) -> String {
        String(format: String(localized: "Profile %lld", bundle: .module), number)
    }

    /// "Work Copy": the name of a duplicate.
    public static func copyName(_ name: String) -> String {
        String(format: String(localized: "%@ Copy", bundle: .module), name)
    }

    public static func deleteProfileQuestion(_ name: String) -> String {
        String(format: String(localized: "Delete the profile “%@”? The menu bar stays as it is now.", bundle: .module), name)
    }

    /// A profile's name, or a stand-in for one saved without a name.
    public static func name(of profile: Profile) -> String {
        profile.name.isEmpty ? untitledProfile : profile.name
    }

    // MARK: Tiroir's menu

    public static let profilesMenu = String(localized: "Profiles", bundle: .module)
}

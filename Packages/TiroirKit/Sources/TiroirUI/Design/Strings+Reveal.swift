import Foundation

/// Words of Show Every Icon from the menu bar, icon shortcuts, the settings file and diagnostics.
extension Strings {
    // MARK: Behavior, Tiroir's own icons

    public static let keepItemsAtRightEnd = String(localized: "Keep Tiroir's icons next to Control Center", bundle: .module)
    public static let keepItemsAtRightEndNote = String(localized: "Tiroir's icon, then your drawers in the order set in Drawers. Turn it off to place them yourself with a Command-drag.", bundle: .module)

    // MARK: Behavior, Show every icon

    public static let revealSection = String(localized: "Show every icon", bundle: .module)
    public static let revealOnHover = String(localized: "When the pointer rests on the menu bar", bundle: .module)
    public static let revealOnClick = String(localized: "When you click an empty part of the menu bar", bundle: .module)
    public static let revealOnScroll = String(localized: "When you scroll or swipe in the menu bar", bundle: .module)
    public static let revealOnScrollNote = String(localized: "Scroll again to hide them.", bundle: .module)
    public static let revealEmptyNote = String(localized: "Only on empty room: the icons and the app's menus keep their clicks.", bundle: .module)
    public static let revealPlace = String(localized: "Show them", bundle: .module)
    public static let revealInMenuBar = String(localized: "In the Menu Bar", bundle: .module)
    public static let revealInAllDrawer = String(localized: "In the All Drawer", bundle: .module)
    public static let revealPlaceNotchNote = String(localized: "Beside the notch, the All drawer shows every icon even when they do not all fit.", bundle: .module)
    public static let hideAgainAutomatically = String(localized: "Hide them again automatically", bundle: .module)
    public static let hideAgainNote = String(localized: "Once the pointer has left the menu bar this long and no menu is open.", bundle: .module)

    // MARK: Layout, room

    public static let moveOverflowAutomatically = String(localized: "Move icons that stop fitting into a drawer automatically", bundle: .module)
    public static let moveOverflowAutomaticallyNote = String(localized: "They join Other as soon as the room runs out.", bundle: .module)

    public static let iconSpacingRow = String(localized: "Space between icons", bundle: .module)
    public static let iconSpacingNote = String(localized: "For every app on this Mac. macOS uses it as apps open, and on every icon once you log out and back in.", bundle: .module)
    public static let iconSpacingPending = String(localized: "Log out and back in to see it on every icon.", bundle: .module)
    public static let spacingStandard = String(localized: "Standard", bundle: .module)
    public static let spacingSnug = String(localized: "Snug", bundle: .module)
    public static let spacingCompact = String(localized: "Compact", bundle: .module)
    public static let spacingTight = String(localized: "Tight", bundle: .module)

    // MARK: Shortcuts

    public static let showEveryIconShortcut = String(localized: "Show every icon", bundle: .module)
    public static let showEveryIconShortcutNote = String(localized: "Press it again to hide them.", bundle: .module)
    public static let iconShortcutsSection = String(localized: "Icons", bundle: .module)
    public static let iconShortcutsNote = String(localized: "A shortcut opens an icon's menu, wherever the icon lives.", bundle: .module)
    public static let addIconShortcut = String(localized: "Add Icon Shortcut", bundle: .module)
    public static let noIconShortcuts = String(localized: "No icon has a shortcut yet.", bundle: .module)
    public static let removeShortcut = String(localized: "Remove Shortcut", bundle: .module)
    public static let addShortcutMenuItem = String(localized: "Add Shortcut…", bundle: .module)

    // MARK: General, settings file and help

    public static let settingsFileSection = String(localized: "Settings file", bundle: .module)
    public static let settingsFileRow = String(localized: "Your drawers, profiles and settings", bundle: .module)
    public static let settingsFileNote = String(localized: "A file to keep a copy, or to set up another Mac the same way.", bundle: .module)
    public static let exportSettings = String(localized: "Export…", bundle: .module)
    public static let importSettings = String(localized: "Import…", bundle: .module)
    public static let exportFileName = String(localized: "Tiroir Settings", bundle: .module)
    public static func importQuestion(_ fileName: String) -> String {
        String(format: String(localized: "Replace your setup with “%@”?", bundle: .module), fileName)
    }
    public static let importExplanation = String(localized: "Your drawers and settings are replaced by the ones in the file. Export them first to keep a copy.", bundle: .module)
    public static let replace = String(localized: "Replace", bundle: .module)
    public static let importUnreadable = String(localized: "This file is not a Tiroir settings file.", bundle: .module)
    public static let importFromNewerVersion = String(localized: "This file comes from a newer version of Tiroir. Update Tiroir, then import it again.", bundle: .module)
    public static let helpSection = String(localized: "Help", bundle: .module)
    public static let welcomeRow = String(localized: "Welcome", bundle: .module)
    public static let welcomeRowNote = String(localized: "The short tour, Accessibility and Smart Sort, as on the first launch.", bundle: .module)
    public static let showAgain = String(localized: "Show Again", bundle: .module)
    public static let reportProblemRow = String(localized: "Report a problem", bundle: .module)
    public static let copyDiagnostics = String(localized: "Copy Diagnostics", bundle: .module)
    public static let diagnosticsNote = String(localized: "For a bug report: your Mac, your macOS, what Tiroir sees in the menu bar and its recent messages. Nothing is sent; you choose where to paste it.", bundle: .module)
    public static let diagnosticsCopied = String(localized: "Diagnostics copied", bundle: .module)
}

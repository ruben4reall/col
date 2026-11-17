import Foundation
import TiroirCore

/// Every word the interface shows. Each one is a key of `Resources/Localizable.xcstrings`, so another language needs no
/// code change, and views never write a user-facing literal: `StringCatalogTests` checks both. Strings with a value
/// use a format key (`%lld`, `%@`) filled with `String(format:)`.
public enum Strings {
    // MARK: Tiroir

    public static let appName = String(localized: "Tiroir", bundle: .module)
    public static let tagline = String(localized: "Your menu bar, in drawers.", bundle: .module)
    public static let signature = String(localized: "A place for every icon.", bundle: .module)

    // MARK: Common

    public static let continueButton = String(localized: "Continue", bundle: .module)
    public static let back = String(localized: "Back", bundle: .module)
    public static let done = String(localized: "Done", bundle: .module)
    public static let cancel = String(localized: "Cancel", bundle: .module)
    public static let delete = String(localized: "Delete", bundle: .module)
    public static let reset = String(localized: "Reset", bundle: .module)
    public static let openSystemSettings = String(localized: "Open System Settings", bundle: .module)
    public static let menuBar = String(localized: "Menu Bar", bundle: .module)
    public static let hidden = String(localized: "Hidden", bundle: .module)
    public static let beta = String(localized: "Beta", bundle: .module)

    public static func iconCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 icon", bundle: .module)
            : String(format: String(localized: "%lld icons", bundle: .module), count)
    }

    // MARK: Categories

    public static func categoryName(_ category: CategoryID) -> String {
        switch category {
        case .files: String(localized: "Files & Cloud", bundle: .module)
        case .security: String(localized: "Security & VPN", bundle: .module)
        case .messages: String(localized: "Messages", bundle: .module)
        case .ai: String(localized: "AI", bundle: .module)
        case .developer: String(localized: "Developer", bundle: .module)
        case .media: String(localized: "Music & Video", bundle: .module)
        case .devices: String(localized: "Displays & Devices", bundle: .module)
        case .system: String(localized: "System", bundle: .module)
        case .productivity: String(localized: "Productivity", bundle: .module)
        case .utilities: String(localized: "Utilities", bundle: .module)
        case .design: String(localized: "Design", bundle: .module)
        case .games: String(localized: "Games", bundle: .module)
        case .other: String(localized: "Other", bundle: .module)
        }
    }

    public static let allIcons = String(localized: "All Icons", bundle: .module)

    // MARK: Menu bar items

    public static let searchIconsMenuItem = String(localized: "Search Icons…", bundle: .module)
    public static let showEveryIcon = String(localized: "Show Every Icon", bundle: .module)
    public static let hideThemAgain = String(localized: "Hide Them Again", bundle: .module)
    public static let focus = String(localized: "Focus", bundle: .module)
    public static let endFocus = String(localized: "End Focus", bundle: .module)
    public static let editDrawerMenuItem = String(localized: "Edit Drawer…", bundle: .module)
    public static let settingsMenuItem = String(localized: "Settings…", bundle: .module)
    public static let checkForUpdates = String(localized: "Check for Updates…", bundle: .module)
    public static let quitTiroir = String(localized: "Quit Tiroir", bundle: .module)
    public static let focusIsOnHelp = String(localized: "Focus is on: only the clock and Control Center show. Click to end it.", bundle: .module)
    public static let tiroirIconHelp = String(localized: "Click for every drawer. Right-click for more.", bundle: .module)

    public static func drawerAccessibilityLabel(_ name: String) -> String {
        String(format: String(localized: "%@ drawer", bundle: .module), name)
    }

    // MARK: Drawers

    public static let editThisDrawer = String(localized: "Edit this drawer", bundle: .module)
    public static let emptyDrawerTitle = String(localized: "This drawer is empty.", bundle: .module)
    public static let emptyDrawerHint = String(localized: "Drag icons into it in Settings, Layout.", bundle: .module)
    public static let open = String(localized: "Open", bundle: .module)
    public static let moveTo = String(localized: "Move To", bundle: .module)
    public static let keepInMenuBar = String(localized: "Keep in Menu Bar", bundle: .module)
    public static let hide = String(localized: "Hide", bundle: .module)
    public static let showInFinder = String(localized: "Show in Finder", bundle: .module)
    public static let filter = String(localized: "Filter", bundle: .module)
    /// The drawer's filter for VoiceOver, with what is typed in it.
    public static func filterLabel(_ text: String) -> String {
        String(format: String(localized: "Filter: %@", bundle: .module), text)
    }
    public static let noHiddenIcons = String(localized: "Nothing hidden and no drawers yet.", bundle: .module)

    public static func couldNotOpen(_ name: String) -> String {
        String(format: String(localized: "Tiroir could not open %@.", bundle: .module), name)
    }

    public static let needsAccessibilityToOpen = String(localized: "Tiroir needs Accessibility to open icons.", bundle: .module)

    // MARK: Search

    public static let searchPlaceholder = String(localized: "Search menu bar icons", bundle: .module)

    public static func noSearchResult(_ query: String) -> String {
        String(format: String(localized: "No icon matches “%@”.", bundle: .module), query)
    }

    // MARK: Welcome

    public static let welcomeWindowTitle = String(localized: "Welcome to Tiroir", bundle: .module)
    public static let welcomeTitle = String(localized: "Welcome to Tiroir", bundle: .module)
    public static let welcomeBody = String(localized: "Tiroir sorts the icons of your menu bar into drawers, each one a single icon. The menu bar keeps what you look at all day; everything else waits in a drawer, one click away.", bundle: .module)
    public static let permissionTitle = String(localized: "One permission", bundle: .module)
    public static let permissionBody = String(localized: "Tiroir needs Accessibility to see which app owns each icon and to open them for you. It never records your screen and never goes online, except to check for updates.", bundle: .module)
    public static let permissionWaiting = String(localized: "Waiting for Accessibility…", bundle: .module)
    public static let permissionGranted = String(localized: "Accessibility is on.", bundle: .module)
    public static let permissionSteps = String(localized: "In System Settings, turn on Tiroir under Privacy & Security, Accessibility.", bundle: .module)
    public static let tahoePointerNote = String(localized: "On macOS 26, Tiroir arranges icons with Command-drags, as you would: the pointer may blink while it works.", bundle: .module)
    public static let applicationsFolderNote = String(localized: "macOS 27 lets only apps in the Applications folder change the menu bar.", bundle: .module)
    public static let moveToApplications = String(localized: "Move to Applications", bundle: .module)
    public static let skipForNow = String(localized: "Skip for Now", bundle: .module)
    public static let moveToApplicationsQuestion = String(localized: "Move Tiroir to the Applications folder?", bundle: .module)
    public static let moveToApplicationsReason = String(localized: "Tiroir works best from Applications: it can open at login and update itself there, and macOS 27 lets only apps there change the menu bar.", bundle: .module)
    public static let notNow = String(localized: "Not Now", bundle: .module)
    public static let smartSortTitle = String(localized: "Smart Sort", bundle: .module)

    public static func smartSortFound(_ count: Int) -> String {
        String(format: String(localized: "Tiroir found %lld icons. Here is a tidier menu bar.", bundle: .module), count)
    }

    public static let byPurpose = String(localized: "By Purpose", bundle: .module)
    public static let byDeveloper = String(localized: "By Developer", bundle: .module)
    public static let oneDrawer = String(localized: "One Drawer", bundle: .module)
    public static let smartSortHint = String(localized: "Drag an icon to another drawer. Click a drawer's own icon to change it.", bundle: .module)

    public static func iconsLeaveMenuBar(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 icon leaves the menu bar.", bundle: .module)
            : String(format: String(localized: "%lld icons leave the menu bar.", bundle: .module), count)
    }

    public static let sortMyMenuBar = String(localized: "Sort My Menu Bar", bundle: .module)
    public static let startEmpty = String(localized: "Start Empty", bundle: .module)
    public static let sorting = String(localized: "Sorting your menu bar…", bundle: .module)

    public static func couldNotMove(count: Int) -> String {
        count == 1
            ? String(localized: "1 icon could not be moved. You can move it in Settings, Layout.", bundle: .module)
            : String(format: String(localized: "%lld icons could not be moved. You can move them in Settings, Layout.", bundle: .module), count)
    }

    public static let readyTitle = String(localized: "Ready", bundle: .module)

    public static func readyBody(search: String) -> String {
        String(format: String(localized: "Click a drawer in the menu bar to open it, and search any icon with %@.", bundle: .module), search)
    }

    public static let readyBodyWithoutShortcut = String(localized: "Click a drawer in the menu bar to open it, and Tiroir's own icon for all of them.", bundle: .module)
    public static let openAtLogin = String(localized: "Open at Login", bundle: .module)
    public static let keepUpToDate = String(localized: "Keep Tiroir Up to Date", bundle: .module)
    public static let noIconsFound = String(localized: "Tiroir does not see any icon to sort yet. Your drawers will fill as apps add theirs.", bundle: .module)

    // MARK: Settings

    public static let settingsWindowTitle = String(localized: "Tiroir Settings", bundle: .module)
    public static let layout = String(localized: "Layout", bundle: .module)
    public static let drawers = String(localized: "Drawers", bundle: .module)
    public static let appearance = String(localized: "Appearance", bundle: .module)
    public static let behavior = String(localized: "Behavior", bundle: .module)
    public static let shortcuts = String(localized: "Shortcuts", bundle: .module)
    public static let general = String(localized: "General", bundle: .module)
    public static let about = String(localized: "About", bundle: .module)

    // MARK: Layout

    public static let layoutSubtitle = String(localized: "Drag icons between the menu bar, your drawers and Hidden.", bundle: .module)
    public static let hiddenSubtitle = String(localized: "Out of the menu bar. Reach them from search or Tiroir's icon.", bundle: .module)
    public static let menuBarSubtitle = String(localized: "Always in the menu bar.", bundle: .module)
    public static let smartSortButton = String(localized: "Smart Sort…", bundle: .module)
    public static let newDrawer = String(localized: "New Drawer", bundle: .module)
    public static let newDrawerName = String(localized: "New Drawer", bundle: .module)
    public static let roomBesideNotch = String(localized: "Room beside the notch", bundle: .module)
    public static let roomInMenuBar = String(localized: "Room in the menu bar", bundle: .module)

    public static func roomUsed(_ used: Int, of room: Int) -> String {
        String(format: String(localized: "%lld of %lld points", bundle: .module), used, room)
    }

    public static func iconsDoNotFit(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 icon does not fit beside the notch.", bundle: .module)
            : String(format: String(localized: "%lld icons do not fit beside the notch.", bundle: .module), count)
    }

    public static let moveThemToDrawer = String(localized: "Move Them to a Drawer", bundle: .module)
    public static let fixedByMacOS = String(localized: "macOS keeps the clock and Control Center in place.", bundle: .module)
    public static let appleIconsStayOn27 = String(localized: "On macOS 27, Apple's own icons cannot be hidden.", bundle: .module)

    public static func mixedAppOn27(_ name: String) -> String {
        String(format: String(localized: "On macOS 27, Tiroir hides whole apps: %@ has icons in two places, so it stays in the menu bar.", bundle: .module), name)
    }

    public static func couldNotMoveIcon(_ name: String) -> String {
        String(format: String(localized: "Tiroir could not move %@. Try again, or move it with Command-drag.", bundle: .module), name)
    }

    public static let needsAccessibilityBanner = String(localized: "Tiroir needs Accessibility to see and arrange your icons.", bundle: .module)
    public static let needsApplicationsBanner = String(localized: "Move Tiroir to the Applications folder: macOS 27 only lets apps there change the menu bar.", bundle: .module)

    public static func unavailableBanner(_ detail: String) -> String {
        String(format: String(localized: "This version of macOS changed what Tiroir relies on (%@). Everything stays in the menu bar.", bundle: .module), detail)
    }

    public static let tryAgain = String(localized: "Try Again", bundle: .module)

    // MARK: Drawers pane

    public static let noDrawersYet = String(localized: "No drawers yet. Make one, or let Smart Sort propose them.", bundle: .module)
    public static let name = String(localized: "Name", bundle: .module)
    public static let mark = String(localized: "Mark", bundle: .module)
    public static let showNameInMenuBar = String(localized: "Show the name in the menu bar", bundle: .module)
    public static let showCount = String(localized: "Show how many icons it holds", bundle: .module)
    public static let shortcut = String(localized: "Shortcut", bundle: .module)
    public static let deleteDrawer = String(localized: "Delete Drawer", bundle: .module)

    public static func deleteDrawerQuestion(_ name: String) -> String {
        String(format: String(localized: "Delete “%@”? Its icons go back to the menu bar.", bundle: .module), name)
    }

    public static let emoji = String(localized: "Emoji", bundle: .module)
    public static let icon = String(localized: "Icon", bundle: .module)
    public static let searchIcons = String(localized: "Search icons", bundle: .module)

    /// The themes of the icon library.
    public static func symbolSection(_ title: String) -> String {
        switch title {
        case "Files & Cloud": String(localized: "Files & Cloud", bundle: .module)
        case "Security & Privacy": String(localized: "Security & Privacy", bundle: .module)
        case "Messages & People": String(localized: "Messages & People", bundle: .module)
        case "Developer": String(localized: "Developer", bundle: .module)
        case "AI & Ideas": String(localized: "AI & Ideas", bundle: .module)
        case "Music & Video": String(localized: "Music & Video", bundle: .module)
        case "Devices": String(localized: "Devices", bundle: .module)
        case "System": String(localized: "System", bundle: .module)
        case "Productivity": String(localized: "Productivity", bundle: .module)
        case "Design": String(localized: "Design", bundle: .module)
        case "Games & Fun": String(localized: "Games & Fun", bundle: .module)
        case "Home & Places": String(localized: "Home & Places", bundle: .module)
        case "Nature & Weather": String(localized: "Nature & Weather", bundle: .module)
        case "Shapes": String(localized: "Shapes", bundle: .module)
        case "Arrows": String(localized: "Arrows", bundle: .module)
        default: title
        }
    }
    public static let text = String(localized: "Text", bundle: .module)
    public static let moreEmoji = String(localized: "More Emoji…", bundle: .module)
    public static let upToThreeLetters = String(localized: "Up to 3 letters", bundle: .module)

    // MARK: Appearance

    public static let menuBarTint = String(localized: "Menu bar tint", bundle: .module)
    public static let tintNone = String(localized: "None", bundle: .module)
    public static let tintColor = String(localized: "Color", bundle: .module)
    public static let tintGradient = String(localized: "Gradient", bundle: .module)
    public static let gradientEnd = String(localized: "Gradient end", bundle: .module)
    public static let strength = String(localized: "Strength", bundle: .module)
    public static let hairlineBorder = String(localized: "Hairline border", bundle: .module)
    public static let softShadow = String(localized: "Soft shadow", bundle: .module)
    public static let tintNote = String(localized: "The tint shows while the menu bar has no background of its own (System Settings, Menu Bar).", bundle: .module)
    public static let preview = String(localized: "Preview", bundle: .module)

    // MARK: Behavior

    public static let newIcons = String(localized: "New icons", bundle: .module)
    public static let sortIntoTheirDrawer = String(localized: "Sort into their drawer", bundle: .module)
    public static let showInMenuBar = String(localized: "Show in the menu bar", bundle: .module)
    public static let hideNewIcons = String(localized: "Hide", bundle: .module)
    public static let openOnHover = String(localized: "Open drawers on hover", bundle: .module)
    public static let hoverDelay = String(localized: "Delay", bundle: .module)
    public static let returnIconsAfter = String(localized: "Put opened icons back after", bundle: .module)
    public static let returnIconsNote = String(localized: "An icon opened from a drawer goes back once its menu has been closed this long.", bundle: .module)
    public static let optionClickShowsEverything = String(localized: "Option-click Tiroir's icon to show every icon", bundle: .module)
    public static let showTiroirIcon = String(localized: "Show Tiroir's icon in the menu bar", bundle: .module)
    public static let showTiroirIconNote = String(localized: "Without it, right-click any drawer for Settings.", bundle: .module)
    public static let engine = String(localized: "Menu bar engine", bundle: .module)
    public static let engineTahoe = String(localized: "macOS 26: Tiroir moves icons behind an invisible divider.", bundle: .module)
    public static let engineGoldenGate = String(localized: "macOS 27: Tiroir asks macOS to hide whole apps.", bundle: .module)
    public static let engineDemo = String(localized: "Demo: generic icons, nothing in your menu bar moves.", bundle: .module)
    public static let goldenGateSideEffects = String(localized: "While icons are hidden, macOS 27 also hides Focus and the camera and microphone indicators.", bundle: .module)

    public static func seconds(_ value: String) -> String {
        String(format: String(localized: "%@ s", bundle: .module), value)
    }

    // MARK: Shortcuts

    public static let searchIconsShortcut = String(localized: "Search icons", bundle: .module)
    public static let openAllDrawers = String(localized: "Open all drawers", bundle: .module)
    public static let focusShortcut = String(localized: "Focus", bundle: .module)
    public static let focusShortcutNote = String(localized: "Everything but the clock and Control Center leaves the menu bar, for a presentation or a screen share.", bundle: .module)
    public static let recordShortcut = String(localized: "Record Shortcut", bundle: .module)
    public static let pressShortcut = String(localized: "Press a shortcut…", bundle: .module)
    public static let clear = String(localized: "Clear", bundle: .module)
    public static let needsModifier = String(localized: "Use ⌘, ⌥ or ⌃ with the key.", bundle: .module)
    public static let shortcutTaken = String(localized: "Another app already uses this shortcut.", bundle: .module)

    // MARK: General

    public static let loginNeedsApproval = String(localized: "Allow Tiroir in System Settings, General, Login Items & Extensions.", bundle: .module)
    public static let updates = String(localized: "Updates", bundle: .module)
    public static let checkAutomatically = String(localized: "Check for updates automatically", bundle: .module)
    public static let checkNow = String(localized: "Check Now", bundle: .module)
    public static let accessibility = String(localized: "Accessibility", bundle: .module)
    public static let on = String(localized: "On", bundle: .module)
    public static let off = String(localized: "Off", bundle: .module)
    public static let memory = String(localized: "Memory", bundle: .module)

    public static func memoryInUse(_ amount: String) -> String {
        String(format: String(localized: "%@ in use", bundle: .module), amount)
    }

    public static let pauseTiroir = String(localized: "Show every icon and pause Tiroir", bundle: .module)
    public static let resetLayout = String(localized: "Reset Layout…", bundle: .module)
    public static let resetLayoutQuestion = String(localized: "Reset your layout? Every icon goes back to the menu bar and Tiroir shows its welcome again.", bundle: .module)

    // MARK: Main menu

    public static let aboutTiroir = String(localized: "About Tiroir", bundle: .module)
    public static let editMenu = String(localized: "Edit", bundle: .module)
    public static let undo = String(localized: "Undo", bundle: .module)
    public static let redo = String(localized: "Redo", bundle: .module)
    public static let cut = String(localized: "Cut", bundle: .module)
    public static let copy = String(localized: "Copy", bundle: .module)
    public static let paste = String(localized: "Paste", bundle: .module)
    public static let selectAll = String(localized: "Select All", bundle: .module)
    public static let windowMenu = String(localized: "Window", bundle: .module)
    public static let close = String(localized: "Close", bundle: .module)
    public static let minimize = String(localized: "Minimize", bundle: .module)

    // MARK: About

    public static func version(_ value: String) -> String {
        String(format: String(localized: "Version %@", bundle: .module), value)
    }

    public static let freeAndOpenSource = String(localized: "Free and open source, under the MIT License.", bundle: .module)
    public static let website = String(localized: "Website", bundle: .module)
    public static let sourceCode = String(localized: "Source Code", bundle: .module)
    public static let reportIssue = String(localized: "Report an Issue", bundle: .module)
    public static let creditsLine = String(localized: "Updates by Sparkle. Techniques from Hidden Bar, MenuBarHider and Ellipsis, rewritten for Tiroir.", bundle: .module)
    public static let notAffiliated = String(localized: "Tiroir is not affiliated with Apple.", bundle: .module)
}

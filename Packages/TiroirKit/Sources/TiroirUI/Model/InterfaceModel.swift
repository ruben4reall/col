import AppKit
import Observation
import TiroirCore
import TiroirSystem

/// One icon as the interface shows it: the scan's facts plus the app's name, icon and kind.
public struct IconRow: Identifiable, Equatable {
    public var id: IconID
    /// "Google Drive", or the module's label for macOS icons ("Battery").
    public var name: String
    /// The icon's own label, when it says more than the name.
    public var label: String?
    public var appName: String
    public var appIcon: NSImage
    public var category: CategoryID
    public var developer: String
    public var kind: IconKind
    public var isMovable: Bool
    public var isRunning: Bool
    public var frame: CGRect

    public init(
        id: IconID, name: String, label: String? = nil, appName: String, appIcon: NSImage, category: CategoryID,
        developer: String, kind: IconKind, isMovable: Bool, isRunning: Bool = true, frame: CGRect = .zero
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.appName = appName
        self.appIcon = appIcon
        self.category = category
        self.developer = developer
        self.kind = kind
        self.isMovable = isMovable
        self.isRunning = isRunning
        self.frame = frame
    }

    public static func == (lhs: IconRow, rhs: IconRow) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.label == rhs.label && lhs.category == rhs.category
            && lhs.isMovable == rhs.isMovable && lhs.isRunning == rhs.isRunning && lhs.frame == rhs.frame
            && lhs.appIcon === rhs.appIcon
    }

    /// The label worth showing under the name: only when it adds something.
    public var subtitle: String? {
        guard let label, !label.isEmpty, label != name, !label.hasPrefix(name) else { return nil }
        return label
    }
}

/// What the app tells the interface it can do. The coordinator in TiroirApp fills it in.
@MainActor
public struct InterfaceActions {
    public var updateSettings: (TiroirSettings) -> Void = { _ in }
    public var openIcon: (IconID, UUID?) -> Void = { _, _ in }
    public var propose: (SortStrategy) -> Layout = { _ in .empty }
    public var applySmartSort: (Layout, SortStrategy) async -> ApplyReport = { _, _ in .nothing }
    public var requestAccessibility: () -> Void = {}
    public var openAccessibilitySettings: () -> Void = {}
    public var moveToApplications: () -> Void = {}
    public var setOpenAtLogin: (Bool) -> Void = { _ in }
    public var setAutomaticUpdates: (Bool) -> Void = { _ in }
    public var checkForUpdates: () -> Void = {}
    public var toggleFocus: () -> Void = {}
    public var toggleShowEverything: () -> Void = {}
    public var resetLayout: () -> Void = {}
    public var retry: () -> Void = {}
    public var openSettings: (SettingsPane) -> Void = { _ in }
    public var finishWelcome: () -> Void = {}
    public var showInFinder: (IconID) -> Void = { _ in }
    public var refreshMemory: () -> Void = {}
    public var quit: () -> Void = {}
    /// Switches to a profile by hand; the menu bar follows at once.
    public var switchProfile: (UUID) -> Void = { _ in }
    public var exportSettings: () -> Void = {}
    public var importSettings: () -> Void = {}
    public var showWelcomeAgain: () -> Void = {}
    public var copyDiagnostics: () -> Void = {}
    public var setIconSpacing: (IconSpacing) -> Void = { _ in }

    public init() {}
}

/// Settings' sections.
public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case layout, drawers, profiles, triggers, appearance, behavior, shortcuts, general, about
    public var id: String { rawValue }
}

/// Everything the drawers, search, the welcome and Settings show, on the main actor.
@MainActor
@Observable
public final class InterfaceModel {
    public var settings: TiroirSettings
    /// Every icon Tiroir knows, from right to left in the menu bar.
    public var icons: [IconRow] = []
    public var engineKind: EngineKind = .tahoe
    public var engineStatus: EngineStatus = .ready
    public var capacity: NotchCapacity.Result?
    public var hasNotch = false
    /// macOS 27: apps kept visible because they have icons in two places.
    public var conflicts: Set<String> = []
    public var failedMoves: [IconID] = []
    public var isFocusOn = false
    public var isShowingEverything = false
    public var isApplying = false
    public var applyProgress: (done: Int, total: Int)?
    public var memoryBytes: UInt64?
    public var loginItemStatus: LoginItemStatus = .disabled
    public var automaticUpdates = true
    public var canCheckForUpdates = true
    public var accessibilityTrusted = false
    public var isInApplications = true
    public var appVersion = "1.0.0"
    public var settingsPane: SettingsPane = .layout
    /// Shortcuts macOS refused because another app holds them: "search", "allDrawer", "focus", "showEverything", a
    /// drawer's id, or "icon:" and an icon's description.
    public var refusedShortcuts: Set<String> = []
    /// The drawer Settings shows in the Drawers pane.
    public var selectedDrawer: UUID?
    /// Triggers whose condition holds now: Settings marks them "Active now".
    public var activeTriggers: Set<UUID> = []
    /// An icon about to get a shortcut: the Shortcuts pane shows its recorder, waiting for the keys.
    public var pendingIconShortcut: IconID?
    /// The room macOS leaves between icons, and whether it changed since the last login.
    public var iconSpacing: IconSpacing = .standard
    public var iconSpacingChanged = false
    public var actions = InterfaceActions()

    public init(settings: TiroirSettings = .defaults) {
        self.settings = settings
    }

    // MARK: Reading the layout

    public func row(_ id: IconID) -> IconRow? {
        icons.first { $0.id == id }
    }

    public func placement(of row: IconRow) -> Placement {
        guard row.isMovable else { return .menuBar }
        return settings.layout.placement(of: row.id, category: row.category)
    }

    public func members(of drawer: UUID) -> [IconRow] {
        icons.filter { placement(of: $0) == .drawer(drawer) }
    }

    public var hiddenRows: [IconRow] {
        icons.filter { placement(of: $0) == .hidden }
    }

    public var menuBarRows: [IconRow] {
        icons.filter { placement(of: $0) == .menuBar }
    }

    public func drawer(_ id: UUID) -> Drawer? {
        settings.layout.drawer(id)
    }

    /// Where an icon lives, in words: a drawer's name, Menu Bar or Hidden.
    public func placeName(of row: IconRow) -> String {
        switch placement(of: row) {
        case .menuBar: Strings.menuBar
        case .hidden: Strings.hidden
        case .drawer(let id): drawer(id)?.name ?? Strings.menuBar
        }
    }

    // MARK: Changing the layout

    /// Changes the settings. While a profile is active, it follows every change of the layout and the appearance.
    public func update(_ change: (inout TiroirSettings) -> Void) {
        var copy = settings
        change(&copy)
        copy.writeThrough()
        guard copy != settings else { return }
        settings = copy
        actions.updateSettings(copy)
    }

    public func move(_ id: IconID, to placement: Placement) {
        update { $0.layout.assign(id, to: placement) }
    }

    public func addDrawer() -> UUID {
        let drawer = Drawer(name: Strings.newDrawerName, mark: .symbol("folder.fill"))
        update { $0.layout.addDrawer(drawer) }
        selectedDrawer = drawer.id
        return drawer.id
    }

    public func updateDrawer(_ drawer: Drawer) {
        update { $0.layout.updateDrawer(drawer) }
    }

    public func removeDrawer(_ id: UUID) {
        update { $0.layout.removeDrawer(id) }
        if selectedDrawer == id { selectedDrawer = settings.layout.drawers.first?.id }
    }

    // MARK: Profiles

    /// Saves the current setup as a new profile, which becomes active.
    @discardableResult
    public func saveCurrentAsProfile(named name: String) -> UUID {
        let id = UUID()
        update { $0.saveCurrentAsProfile(named: name, id: id) }
        return id
    }

    public func switchProfile(to id: UUID) {
        actions.switchProfile(id)
    }

    // MARK: Triggers

    /// Adds a trigger, or replaces the one with the same identity.
    public func saveTrigger(_ trigger: Trigger) {
        update { settings in
            if let index = settings.triggers.firstIndex(where: { $0.id == trigger.id }) {
                settings.triggers[index] = trigger.clamped
            } else {
                settings.triggers.append(trigger.clamped)
            }
        }
    }

    public func removeTrigger(_ id: UUID) {
        update { $0.triggers.removeAll { $0.id == id } }
    }

    /// Moves the icons that do not fit beside the notch into a drawer (Other, made if needed).
    public func moveOverflowIntoDrawer() {
        guard let overflow = capacity?.overflow, !overflow.isEmpty else { return }
        update { settings in
            let target: UUID
            if let other = settings.layout.drawer(for: .other) {
                target = other.id
            } else {
                let drawer = Drawer(name: Strings.categoryName(.other), mark: .symbol(CategoryID.other.symbol), category: .other)
                settings.layout.addDrawer(drawer)
                target = drawer.id
            }
            for id in overflow where id.bundleID != TiroirInfo.bundleIdentifier { settings.layout.assign(id, to: .drawer(target)) }
        }
    }
}

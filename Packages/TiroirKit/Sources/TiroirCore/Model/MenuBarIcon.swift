import CoreGraphics
import Foundation

/// Who draws an icon.
public enum IconKind: String, Codable, Sendable {
    /// A third-party app's icon.
    case app
    /// An icon of macOS itself: Control Center's modules, Spotlight, the input menu.
    case system
}

/// One icon as a scan of the menu bar sees it.
public struct MenuBarIcon: Equatable, Sendable, Identifiable {
    public var id: IconID
    /// The owning app's name, "Google Drive".
    public var ownerName: String
    /// The icon's own label for display ("Battery", "Wi-Fi"), from Accessibility. Never part of the identity.
    public var label: String?
    /// Screen coordinates with the origin at the top left of the main display, as Accessibility and the window
    /// server report them.
    public var frame: CGRect
    /// Whether macOS draws it on a display right now.
    public var isOnScreen: Bool
    /// Whether Tiroir can take it out of the menu bar (the clock and Control Center stay; on macOS 27 no system
    /// module can be hidden).
    public var isMovable: Bool
    public var kind: IconKind
    /// The window that shows it, on macOS 26 only.
    public var windowID: UInt32?
    /// The owning process.
    public var pid: Int32

    public init(
        id: IconID, ownerName: String, label: String? = nil, frame: CGRect, isOnScreen: Bool = true,
        isMovable: Bool = true, kind: IconKind = .app, windowID: UInt32? = nil, pid: Int32 = 0
    ) {
        self.id = id
        self.ownerName = ownerName
        self.label = label
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.isMovable = isMovable
        self.kind = kind
        self.windowID = windowID
        self.pid = pid
    }

    /// The name people know it by: the app's name, or the module's label for Control Center.
    public var displayName: String {
        if kind == .system, let label, !label.isEmpty { return label }
        return ownerName
    }
}

/// Every icon of the menu bar at one moment, from right to left (the clock first).
public struct MenuBarSnapshot: Equatable, Sendable {
    public var icons: [MenuBarIcon]
    public var takenAt: Date

    public init(icons: [MenuBarIcon], takenAt: Date = Date()) {
        self.icons = icons.sorted { $0.frame.midX > $1.frame.midX }
        self.takenAt = takenAt
    }

    public static let empty = MenuBarSnapshot(icons: [])

    public func icon(_ id: IconID) -> MenuBarIcon? {
        icons.first { $0.id == id }
    }

    public var ids: [IconID] { icons.map(\.id) }

    /// The apps that own at least one icon.
    public var bundleIDs: Set<String> { Set(icons.map(\.id.bundleID)) }
}

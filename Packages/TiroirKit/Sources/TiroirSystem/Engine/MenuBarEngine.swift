import CoreGraphics
import Foundation
import TiroirCore

/// Which engine runs (spec 4).
public enum EngineKind: String, Sendable {
    /// macOS 26: a divider pushes icons off screen, synthetic Command-drags move them.
    case tahoe
    /// macOS 27: MenuBarAgent's restriction hides whole apps.
    case goldenGate
    /// Generic icons, for the website's pictures and for trying Tiroir without touching the menu bar.
    case demo
}

/// Whether the engine can work right now.
public enum EngineStatus: Equatable, Sendable {
    case ready
    /// Accessibility is not granted: everything shows, nothing moves.
    case needsAccessibility
    /// macOS 27 only honours apps that run from /Applications.
    case needsApplicationsFolder
    /// A private function this engine needs is missing on this macOS.
    case unavailable(String)
}

public enum EngineError: Error, Equatable, Sendable {
    case notReady(EngineStatus)
    case iconNotFound(IconID)
    /// The icon did not land where it was sent, after every attempt.
    case moveFailed(IconID)
    /// The person kept using the mouse or the keyboard; Tiroir waited, then left the move for later rather than
    /// interfere.
    case personIsBusy
    /// MenuBarAgent refused the restriction.
    case restrictionRefused(String)
    /// The icon could not be opened.
    case cannotOpen(IconID)
}

/// What an arrangement did.
public struct ApplyReport: Equatable, Sendable {
    /// Icons now on the side the plan wants, that were not there before.
    public var moved: [IconID]
    /// Icons Tiroir tried to move, in vain.
    public var failed: [IconID]
    /// Icons left for later: the person was using the pointer or the keyboard.
    public var postponed: [IconID]
    /// When the engine asks to arrange again by itself: once the person pauses, or a while after a failed move.
    public var tryAgainIn: Duration?

    public init(moved: [IconID] = [], failed: [IconID] = [], postponed: [IconID] = [], tryAgainIn: Duration? = nil) {
        self.moved = moved
        self.failed = failed
        self.postponed = postponed
        self.tryAgainIn = tryAgainIn
    }

    public static let nothing = ApplyReport()
}

/// The part of Tiroir that talks to the menu bar. Two implementations, one per macOS generation; everything above
/// this protocol (drawers, Smart Sort, search, Settings) is shared.
@MainActor
public protocol MenuBarEngine: AnyObject {
    var kind: EngineKind { get }
    var granularity: Granularity { get }
    var status: EngineStatus { get }
    /// Called when `status` changes.
    var onStatusChange: (@MainActor (EngineStatus) -> Void)? { get set }

    /// Prepares the engine (the divider on macOS 26, the restriction bridge on 27).
    func start() async
    /// Every icon of other apps and of macOS in the menu bar, Tiroir's own excluded.
    func scan() async -> MenuBarSnapshot
    /// Makes the menu bar match the plan: visible icons show, concealed ones do not.
    func apply(_ plan: VisibilityPlan) async -> ApplyReport
    /// Opens one icon's menu, as a click on it would. `anchor` is the drawer's mark in the menu bar, in window server
    /// coordinates; on macOS 26 the icon is brought next to it for the time its menu is open.
    func open(_ icon: IconID, anchor: CGRect?) async throws
    /// Leaves the menu bar as macOS would without Tiroir. Called on quit; must be quick and synchronous.
    func restore()
}

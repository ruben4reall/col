import CoreGraphics
import Foundation

/// What an engine can take out of the menu bar.
public enum Granularity: Sendable, Equatable {
    /// One icon at a time (macOS 26).
    case icon
    /// A whole app at a time (macOS 27): an app with two icons hides both.
    case app
}

/// Which icons show and which do not, as an engine must realise it.
public struct VisibilityPlan: Equatable, Sendable {
    public var visible: Set<IconID>
    public var concealed: Set<IconID>
    /// Apps whose every icon is concealed: on macOS 27, the apps left out of the allow list.
    public var hiddenApps: Set<String>
    /// On macOS 27, apps with icons both in the menu bar and out of it. They stay visible, and Settings says why.
    public var conflicts: Set<String>

    public init(visible: Set<IconID> = [], concealed: Set<IconID> = [], hiddenApps: Set<String> = [], conflicts: Set<String> = []) {
        self.visible = visible
        self.concealed = concealed
        self.hiddenApps = hiddenApps
        self.conflicts = conflicts
    }

    public static let showEverything = VisibilityPlan()
}

/// The side of Tiroir's divider an icon sits on (macOS 26): left of it is out of the menu bar.
public enum Side: Sendable, Equatable {
    case concealed
    case visible
}

/// One icon to carry across the divider.
public struct Move: Equatable, Sendable {
    public var icon: IconID
    public var to: Side

    public init(icon: IconID, to: Side) {
        self.icon = icon
        self.to = to
    }
}

/// Turns a layout into what each engine does. Pure: the same inputs always give the same plan, so a new icon seen
/// in the middle of an arrangement is simply part of the next plan, planned once.
public enum LayoutPlanner {
    public enum Mode: Sendable, Equatable {
        /// The layout as the person made it.
        case normal
        /// Every icon in the menu bar (the All state with Option, and troubleshooting).
        case showEverything
        /// Everything out of the menu bar but what macOS keeps in place, for a presentation or a screen share.
        case focus
    }

    /// - Parameters:
    ///   - shownIcons: icons that show in the menu bar in the normal mode, whatever their place (a trigger's effect).
    ///   - shownDrawers: drawers whose icons show in the menu bar in the normal mode (a trigger's effect).
    public static func plan(
        layout: Layout, snapshot: MenuBarSnapshot, granularity: Granularity, categories: [IconID: CategoryID],
        mode: Mode = .normal, shownIcons: Set<IconID> = [], shownDrawers: Set<UUID> = []
    ) -> VisibilityPlan {
        var visible = Set<IconID>()
        var concealed = Set<IconID>()
        for icon in snapshot.icons {
            let conceal: Bool
            switch mode {
            case .showEverything: conceal = false
            case .focus: conceal = icon.isMovable
            case .normal:
                let placement = layout.placement(of: icon.id, category: categories[icon.id])
                let isShown: Bool
                if shownIcons.contains(icon.id) {
                    isShown = true
                } else if case .drawer(let drawer) = placement {
                    isShown = shownDrawers.contains(drawer)
                } else {
                    isShown = false
                }
                conceal = icon.isMovable && placement.isConcealed && !isShown
            }
            if conceal { concealed.insert(icon.id) } else { visible.insert(icon.id) }
        }

        var hiddenApps = Set<String>()
        var conflicts = Set<String>()
        for (bundleID, icons) in Dictionary(grouping: snapshot.icons, by: \.id.bundleID) {
            let ids = Set(icons.map(\.id))
            if ids.isSubset(of: concealed) {
                hiddenApps.insert(bundleID)
            } else if granularity == .app, !ids.isDisjoint(with: concealed) {
                // macOS 27 hides whole apps: a mixed app stays visible rather than hiding an icon meant to show.
                conflicts.insert(bundleID)
                concealed.subtract(ids)
                visible.formUnion(ids)
            }
        }
        return VisibilityPlan(visible: visible, concealed: concealed, hiddenApps: hiddenApps, conflicts: conflicts)
    }

    /// The icons to carry across the divider on macOS 26, nearest to it first. An icon sits on the concealed side when
    /// its middle is left of the divider's right edge. Icons macOS keeps in place are never moved.
    public static func moves(plan: VisibilityPlan, snapshot: MenuBarSnapshot, dividerFrame: CGRect) -> [Move] {
        let edge = dividerFrame.maxX
        return snapshot.icons
            .filter(\.isMovable)
            .compactMap { icon -> (Move, CGFloat)? in
                let isConcealed = icon.frame.midX < edge
                let distance = abs(icon.frame.midX - edge)
                if plan.concealed.contains(icon.id), !isConcealed { return (Move(icon: icon.id, to: .concealed), distance) }
                if plan.visible.contains(icon.id), isConcealed { return (Move(icon: icon.id, to: .visible), distance) }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}

import Foundation

/// One icon, with what Smart Sort knows about its app.
public struct ProposalInput: Equatable, Sendable {
    public var icon: MenuBarIcon
    public var category: CategoryID
    public var developer: String

    public init(icon: MenuBarIcon, category: CategoryID, developer: String) {
        self.icon = icon
        self.category = category
        self.developer = developer
    }
}

/// Smart Sort's proposal (spec 5): drawers made from what the apps are for, or from who makes them.
public enum SmartSort {
    /// More drawers than this and the menu bar is crowded again.
    public static let maximumDrawers = 6
    /// The mark of the single drawer of the "just one" strategy.
    public static let everythingMark = DrawerMark.symbol("archivebox.fill")

    /// - Parameters:
    ///   - pinned: icons the person wants to keep in the menu bar.
    ///   - names: the localized name of each category, for the drawers' names.
    ///   - everythingName: the name of the single drawer of `.justOne`.
    ///   - previous: the layout being replaced; a drawer made for the same category keeps its identity, name, mark
    ///     and shortcut.
    public static func propose(
        _ inputs: [ProposalInput], strategy: SortStrategy, pinned: Set<IconID> = [],
        maximumDrawers: Int = SmartSort.maximumDrawers, names: (CategoryID) -> String, everythingName: String,
        previous: Layout? = nil, makeID: () -> UUID = UUID.init
    ) -> Layout {
        var layout = Layout(newIconPolicy: previous?.newIconPolicy ?? .sortIntoDrawer)
        var candidates: [ProposalInput] = []
        for input in inputs {
            if staysInMenuBar(input.icon, pinned: pinned) {
                layout.assign(input.icon.id, to: .menuBar)
            } else {
                candidates.append(input)
            }
        }
        guard !candidates.isEmpty else { return layout }

        switch strategy {
        case .justOne:
            let drawer = Drawer(id: makeID(), name: everythingName, mark: everythingMark)
            layout.addDrawer(drawer)
            for input in candidates { layout.assign(input.icon.id, to: .drawer(drawer.id)) }

        case .purpose:
            let groups = Dictionary(grouping: candidates, by: \.category)
            let plan = partition(groups: groups, other: .other, limit: max(1, maximumDrawers)) { lhs, rhs in
                lhs.key.order < rhs.key.order
            }
            for (category, members) in plan.drawers.sorted(by: { $0.key.order < $1.key.order }) {
                let reused = previous?.drawer(for: category)
                let drawer = Drawer(
                    id: reused?.id ?? makeID(), name: reused?.name ?? names(category),
                    mark: reused?.mark ?? .symbol(category.symbol), category: category,
                    showsName: reused?.showsName ?? false, showsCount: reused?.showsCount ?? false,
                    shortcut: reused?.shortcut)
                layout.addDrawer(drawer)
                for input in members { layout.assign(input.icon.id, to: .drawer(drawer.id)) }
            }
            for input in plan.menuBar { layout.assign(input.icon.id, to: .menuBar) }

        case .developer:
            let groups = Dictionary(grouping: candidates, by: \.developer)
            let otherKey = "\u{0}other"
            let plan = partition(groups: groups, other: otherKey, limit: max(1, maximumDrawers)) { lhs, rhs in
                lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
            let ordered = plan.drawers.sorted { lhs, rhs in
                if lhs.key == otherKey { return false }
                if rhs.key == otherKey { return true }
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
            for (developer, members) in ordered {
                let isOther = developer == otherKey
                let drawer = Drawer(
                    id: makeID(), name: isOther ? names(.other) : developer,
                    mark: isOther ? .symbol(CategoryID.other.symbol) : .text(initial(of: developer)),
                    category: isOther ? .other : nil)
                layout.addDrawer(drawer)
                for input in members { layout.assign(input.icon.id, to: .drawer(drawer.id)) }
            }
            for input in plan.menuBar { layout.assign(input.icon.id, to: .menuBar) }
        }
        return layout
    }

    /// Icons Smart Sort never takes out of the menu bar: the ones macOS keeps in place, the ones people glance at
    /// all day, and the pinned ones.
    public static func staysInMenuBar(_ icon: MenuBarIcon, pinned: Set<IconID>) -> Bool {
        !icon.isMovable || pinned.contains(icon.id) || IconIdentity.essentialSystemIdentifiers.contains(icon.id.key)
    }

    /// Groups of two or more icons become drawers; single icons gather in Other, or stay in the menu bar when they
    /// belong to macOS or when Other would hold just one icon; past `limit` drawers, the smallest merge into Other.
    private static func partition<Key: Hashable>(
        groups: [Key: [ProposalInput]], other: Key, limit: Int, tieBreak: ((key: Key, value: [ProposalInput]), (key: Key, value: [ProposalInput])) -> Bool
    ) -> (drawers: [Key: [ProposalInput]], menuBar: [ProposalInput]) {
        var kept = groups.filter { $0.key != other && $0.value.count >= 2 }
            .sorted { lhs, rhs in
                lhs.value.count != rhs.value.count ? lhs.value.count > rhs.value.count : tieBreak(lhs, rhs)
            }
        var menuBar: [ProposalInput] = []
        var pool = groups[other] ?? []
        for (key, members) in groups where key != other && members.count == 1 {
            let single = members[0]
            if single.icon.kind == .system { menuBar.append(single) } else { pool.append(single) }
        }
        while !kept.isEmpty && kept.count + (pool.count >= 2 ? 1 : 0) > limit {
            pool.append(contentsOf: kept.removeLast().value)
        }
        var drawers = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        if pool.count >= 2 {
            drawers[other] = pool
        } else {
            menuBar.append(contentsOf: pool)
        }
        return (drawers, menuBar)
    }

    /// "Google" → "G", "1Password" → "1".
    static func initial(of name: String) -> String {
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "•" }
        return String(first).uppercased()
    }
}

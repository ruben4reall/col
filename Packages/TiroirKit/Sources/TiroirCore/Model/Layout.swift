import Foundation

/// Where one icon lives.
public enum Placement: Codable, Hashable, Sendable {
    /// In the menu bar, as usual.
    case menuBar
    /// In a drawer: out of the menu bar, in the drawer's panel.
    case drawer(UUID)
    /// Out of the menu bar, reachable from search and the All drawer.
    case hidden

    private enum CodingKeys: String, CodingKey { case kind, drawer }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeIfPresent(String.self, forKey: .kind) {
        case "drawer":
            if let id = try container.decodeIfPresent(UUID.self, forKey: .drawer) {
                self = .drawer(id)
            } else {
                self = .menuBar
            }
        case "hidden": self = .hidden
        default: self = .menuBar
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .menuBar: try container.encode("menuBar", forKey: .kind)
        case .drawer(let id):
            try container.encode("drawer", forKey: .kind)
            try container.encode(id, forKey: .drawer)
        case .hidden: try container.encode("hidden", forKey: .kind)
        }
    }

    /// Out of the menu bar (in a drawer or hidden).
    public var isConcealed: Bool { self != .menuBar }
}

/// Where an icon Tiroir has never seen goes.
public enum NewIconPolicy: String, Codable, Sendable, CaseIterable {
    /// Into the drawer made for its kind, or the menu bar when there is none.
    case sortIntoDrawer
    /// Into the menu bar.
    case menuBar
    /// Hidden.
    case hidden
}

/// Every drawer and every icon's place: the person's arrangement of the menu bar.
public struct Layout: Codable, Hashable, Sendable {
    /// Drawers, left to right as they appear in the menu bar.
    public var drawers: [Drawer]
    /// The place of every icon the person or Smart Sort has placed. An icon missing here follows `newIconPolicy`.
    public var placements: [IconID: Placement]
    public var newIconPolicy: NewIconPolicy

    public init(drawers: [Drawer] = [], placements: [IconID: Placement] = [:], newIconPolicy: NewIconPolicy = .sortIntoDrawer) {
        self.drawers = drawers
        self.placements = placements
        self.newIconPolicy = newIconPolicy
    }

    public static let empty = Layout()

    public func drawer(_ id: UUID) -> Drawer? {
        drawers.first { $0.id == id }
    }

    /// The drawer made for a kind of app, if there is one.
    public func drawer(for category: CategoryID) -> Drawer? {
        drawers.first { $0.category == category }
    }

    /// Where an icon goes: its recorded place, or the new icon policy. A place in a drawer that no longer exists
    /// means the menu bar: deleting a drawer never hides an icon.
    public func placement(of id: IconID, category: CategoryID?) -> Placement {
        if let recorded = placements[id] {
            if case .drawer(let drawerID) = recorded, drawer(drawerID) == nil { return .menuBar }
            return recorded
        }
        switch newIconPolicy {
        case .menuBar: return .menuBar
        case .hidden: return .hidden
        case .sortIntoDrawer:
            if let category, let home = drawer(for: category) { return .drawer(home.id) }
            return .menuBar
        }
    }

    /// Whether Tiroir has placed this icon before.
    public func knows(_ id: IconID) -> Bool { placements[id] != nil }

    public mutating func assign(_ id: IconID, to placement: Placement) {
        placements[id] = placement
    }

    public mutating func addDrawer(_ drawer: Drawer, at index: Int? = nil) {
        guard self.drawer(drawer.id) == nil else { return }
        let position = min(max(index ?? drawers.count, 0), drawers.count)
        drawers.insert(drawer.clamped, at: position)
    }

    public mutating func updateDrawer(_ drawer: Drawer) {
        guard let index = drawers.firstIndex(where: { $0.id == drawer.id }) else { return }
        drawers[index] = drawer.clamped
    }

    /// Removes a drawer; its icons go back to the menu bar.
    public mutating func removeDrawer(_ id: UUID) {
        drawers.removeAll { $0.id == id }
        for (icon, placement) in placements where placement == .drawer(id) {
            placements[icon] = .menuBar
        }
    }

    /// Moves a drawer to a new position among the drawers.
    public mutating func moveDrawer(_ id: UUID, to index: Int) {
        guard let from = drawers.firstIndex(where: { $0.id == id }) else { return }
        let drawer = drawers.remove(at: from)
        drawers.insert(drawer, at: min(max(index, 0), drawers.count))
    }

    /// A drawer's icons, in menu bar order, among those a snapshot sees.
    public func members(of drawer: UUID, in snapshot: MenuBarSnapshot, categories: [IconID: CategoryID]) -> [MenuBarIcon] {
        snapshot.icons.filter { $0.isMovable && placement(of: $0.id, category: categories[$0.id]) == .drawer(drawer) }
    }

    /// Icons placed out of the menu bar without a drawer.
    public func hiddenIcons(in snapshot: MenuBarSnapshot, categories: [IconID: CategoryID]) -> [MenuBarIcon] {
        snapshot.icons.filter { $0.isMovable && placement(of: $0.id, category: categories[$0.id]) == .hidden }
    }

    // Placements are stored as a list of entries: readable, and a malformed entry is skipped instead of losing all.
    private struct Entry: Codable {
        var icon: IconID
        var placement: Placement
    }

    private enum CodingKeys: String, CodingKey { case drawers, placements, newIconPolicy }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        drawers = (try? container.decodeIfPresent([Drawer].self, forKey: .drawers)) ?? []
        let entries = (try? container.decodeIfPresent([FailableEntry].self, forKey: .placements)) ?? []
        placements = Dictionary(entries.compactMap { $0.entry.map { ($0.icon, $0.placement) } }, uniquingKeysWith: { _, last in last })
        newIconPolicy = (try? container.decodeIfPresent(NewIconPolicy.self, forKey: .newIconPolicy)) ?? .sortIntoDrawer
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(drawers, forKey: .drawers)
        let entries = placements.map { Entry(icon: $0.key, placement: $0.value) }.sorted { $0.icon < $1.icon }
        try container.encode(entries, forKey: .placements)
        try container.encode(newIconPolicy, forKey: .newIconPolicy)
    }

    private struct FailableEntry: Decodable {
        var entry: Entry?
        init(from decoder: Decoder) throws {
            entry = try? Entry(from: decoder)
        }
    }
}

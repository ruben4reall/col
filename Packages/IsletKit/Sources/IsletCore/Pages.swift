import Foundation

/// What a page of the open island can hold.
public enum WidgetKind: String, Codable, CaseIterable, Sendable {
    case music, lyrics, clock, agenda, prompter, shelf, clipboard, tools, system

    /// The widths the widget can be drawn at: half a page beside another widget, or the whole page.
    public var widths: Set<WidgetWidth> {
        switch self {
        case .music, .lyrics, .agenda, .prompter: [.half, .full]
        case .clock: [.half]
        case .shelf, .clipboard, .tools, .system: [.full]
        }
    }

    /// False for a widget that has nothing to show at times (the player while nothing plays, lyrics a track has not):
    /// another widget of the same place stands in for it.
    public var alwaysShows: Bool { self != .music && self != .lyrics }
}

public enum WidgetWidth: String, Codable, Sendable {
    case half, full
}

/// One place on a page: widgets in order of preference. The island shows the first one that has something to show,
/// and the last one when none has: the player while music plays, and the clock otherwise.
public struct WidgetStack: Codable, Equatable, Hashable, Sendable {
    public var widgets: [WidgetKind]

    public init(_ widgets: [WidgetKind]) {
        self.widgets = widgets
    }

    /// The widget on show, given which widgets have something to show.
    public func shown(where available: (WidgetKind) -> Bool) -> WidgetKind? {
        widgets.first(where: available) ?? widgets.last
    }
}

/// A page of the open island: one stack across the whole page, or two side by side.
public struct PageLayout: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    /// A name given by the user; nil shows a name made from the page's content.
    public var name: String?
    /// The SF Symbol of the page's tab; nil takes the first widget's.
    public var symbol: String?
    public var stacks: [WidgetStack]

    public init(id: String, name: String? = nil, symbol: String? = nil, stacks: [WidgetStack]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.stacks = stacks
    }

    /// Each widget's width on this page.
    public var width: WidgetWidth { stacks.count == 1 ? .full : .half }

    /// Every widget on the page, in reading order.
    public var widgets: [WidgetKind] { stacks.flatMap(\.widgets) }

    /// Two stacks become one wide one, or one becomes two, keeping every widget that can live at the new width.
    public mutating func setColumns(_ count: Int) {
        guard (1...2).contains(count), count != stacks.count else { return }
        if count == 1 {
            var merged: [WidgetKind] = []
            for kind in widgets where kind.widths.contains(.full) && !merged.contains(kind) { merged.append(kind) }
            stacks = [WidgetStack(merged.isEmpty ? [.agenda] : merged)]
        } else {
            let half = widgets.filter { $0.widths.contains(.half) }
            let first = half.first ?? .clock
            let second = half.dropFirst().first ?? (first == .clock ? .agenda : .clock)
            stacks = [WidgetStack([first]), WidgetStack([second])]
        }
    }
}

/// The user's pages, in tab order.
public struct PageDeck: Codable, Equatable, Sendable {
    public var pages: [PageLayout]

    public init(pages: [PageLayout]) {
        self.pages = pages
    }

    public static let homeID = "home"

    /// The pages Islet starts with: the player with its lyrics beside it (the clock and the agenda while nothing plays),
    /// the prompter, then the tools.
    public static let standard = PageDeck(pages: [
        PageLayout(id: homeID, symbol: "house.fill", stacks: [WidgetStack([.music, .clock]), WidgetStack([.lyrics, .agenda])]),
        PageLayout(id: "prompter", stacks: [WidgetStack([.prompter])]),
        PageLayout(id: "shelf", stacks: [WidgetStack([.shelf])]),
        PageLayout(id: "clipboard", stacks: [WidgetStack([.clipboard])]),
        PageLayout(id: "tools", stacks: [WidgetStack([.tools])]),
        PageLayout(id: "system", stacks: [WidgetStack([.system])]),
    ])

    /// The pages of Islet 1, which kept a list of the optional pages turned on, in order.
    public static func migrating(enabledPages: [String]) -> PageDeck {
        let optional: [String: WidgetKind] = ["prompter": .prompter, "shelf": .shelf, "clipboard": .clipboard, "tools": .tools, "system": .system]
        var pages = [standard.pages[0]]
        for key in enabledPages {
            guard let kind = optional[key], !pages.contains(where: { $0.id == key }) else { continue }
            pages.append(PageLayout(id: key, stacks: [WidgetStack([kind])]))
        }
        return PageDeck(pages: pages)
    }

    /// The deck with everything a page cannot hold taken out: widgets too wide or too narrow for their place,
    /// repeated widgets, empty places and pages, repeated ids. A deck always keeps at least one page.
    public func validated() -> PageDeck {
        var seenIDs: Set<String> = []
        var pages: [PageLayout] = []
        for var page in self.pages {
            guard !page.id.isEmpty, !seenIDs.contains(page.id) else { continue }
            if page.stacks.count > 2 { page.stacks = Array(page.stacks.prefix(2)) }
            // A place that empties can widen the other one, which may then lose widgets too: repeat until it holds.
            var previous: [WidgetStack] = []
            while previous != page.stacks {
                previous = page.stacks
                let width = page.width
                page.stacks = page.stacks.map { stack in
                    var kept: [WidgetKind] = []
                    for kind in stack.widgets where kind.widths.contains(width) && !kept.contains(kind) { kept.append(kind) }
                    return WidgetStack(kept)
                }.filter { !$0.widgets.isEmpty }
            }
            guard !page.stacks.isEmpty else { continue }
            seenIDs.insert(page.id)
            pages.append(page)
        }
        return PageDeck(pages: pages.isEmpty ? [Self.standard.pages[0]] : pages)
    }

    public func page(_ id: String) -> PageLayout? {
        pages.first { $0.id == id }
    }

    /// The first page that holds a widget, to go to it: the shelf when files are dropped on the notch.
    public func firstPage(holding kind: WidgetKind) -> PageLayout? {
        pages.first { $0.widgets.contains(kind) }
    }

    public mutating func move(_ id: String, by offset: Int) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), pages.count - 1)
        guard target != index else { return }
        let page = pages.remove(at: index)
        pages.insert(page, at: target)
    }

    /// Removes a page, unless it is the last one.
    public mutating func remove(_ id: String) {
        guard pages.count > 1 else { return }
        pages.removeAll { $0.id == id }
    }

    /// Adds a page after the others and returns it.
    @discardableResult
    public mutating func add(_ stacks: [WidgetStack], id: String = UUID().uuidString) -> PageLayout {
        let page = PageLayout(id: id, stacks: stacks)
        pages.append(page)
        return page
    }

    public mutating func update(_ page: PageLayout) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[index] = page
    }
}

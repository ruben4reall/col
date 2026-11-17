import AppKit
import SwiftUI
import TiroirCore

/// The glass panel that drops from a drawer's mark (spec 6.2): the drawer's icons as a grid of app icons with their
/// names. Arrow keys move, Return opens, Escape closes, typing filters.
public struct DrawerView: View {
    let model: InterfaceModel
    let target: StatusItemsController.Target
    let onOpen: (IconID) -> Void
    let onClose: () -> Void

    @State private var filter = ""
    @State private var selection: Int?
    @State private var appeared = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maximumColumns = 5
    static let tileWidth: CGFloat = 80
    static let chestLabelWidth: CGFloat = 150
    static let chestTileWidth: CGFloat = 70

    /// Three to five columns: a drawer is as wide as its icons need, never a sliver.
    var columns: Int {
        target == .all ? Self.maximumColumns : min(Self.maximumColumns, max(3, flatRows.count))
    }

    public init(model: InterfaceModel, target: StatusItemsController.Target, onOpen: @escaping (IconID) -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.target = target
        self.onOpen = onOpen
        self.onClose = onClose
    }

    /// The sections shown, each with its icons, filtered.
    var sections: [(id: String, title: String?, mark: DrawerMark?, rows: [IconRow])] {
        let matching: ([IconRow]) -> [IconRow] = { rows in
            guard !filter.isEmpty else { return rows }
            let items = rows.map { SearchItem(id: $0.id, title: $0.name, subtitle: $0.label) }
            let ranked = SearchRanker.rank(filter, in: items).map(\.id)
            return ranked.compactMap { id in rows.first { $0.id == id } }
        }
        switch target {
        case .drawer(let id):
            return [(id.uuidString, nil, nil, matching(model.members(of: id)))]
        case .all:
            var result = model.settings.layout.drawers.map { drawer in
                (drawer.id.uuidString, Optional(drawer.name), Optional(drawer.mark), matching(model.members(of: drawer.id)))
            }
            result.append(("hidden", Strings.hidden, DrawerMark.symbol("eye.slash"), matching(model.hiddenRows)))
            return result.filter { !$0.3.isEmpty || filter.isEmpty && $0.0 != "hidden" }
        }
    }

    var flatRows: [IconRow] { sections.flatMap(\.rows) }

    /// The chest is as wide as its fullest drawer needs, from three icons to five: it never spreads empty room, and it
    /// keeps its width while typing filters it.
    var chestWidth: CGFloat {
        let counts = model.settings.layout.drawers.map { model.members(of: $0.id).count } + [model.hiddenRows.count]
        let widest = min(max(counts.max() ?? 0, 3), Self.maximumColumns)
        return Self.chestLabelWidth + CGFloat(widest) * (Self.chestTileWidth + 4) + 40
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if flatRows.isEmpty && filter.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    if target == .all {
                        // The All drawer is the chest itself: one row per drawer, its mark and name on the left.
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                                if index > 0 { Divider().opacity(0.35).padding(.leading, 4) }
                                chestRow(section)
                            }
                        }
                    } else {
                        grid(sections.first?.rows ?? [])
                    }
                }
                .frame(maxHeight: 480)
            }
        }
        .padding(14)
        .frame(width: target == .all ? chestWidth : CGFloat(columns) * (Self.tileWidth + 6) + 22)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.94, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear {
            focused = true
            withAnimation(reduceMotion ? Motion.fade : Motion.drawer) { appeared = true }
        }
        .onKeyPress(.escape) {
            if filter.isEmpty { onClose() } else { filter = "" }
            return .handled
        }
        .onKeyPress(.return) {
            if let index = selection ?? (flatRows.isEmpty ? nil : 0), flatRows.indices.contains(index) { onOpen(flatRows[index].id) }
            return .handled
        }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(.upArrow) { target == .all ? jumpSection(-1) : step(-columns) }
        .onKeyPress(.downArrow) { target == .all ? jumpSection(1) : step(columns) }
        .onKeyPress(.delete) {
            if !filter.isEmpty { filter.removeLast() }
            return .handled
        }
        .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters).union(.whitespaces)) { press in
            filter += press.characters
            selection = flatRows.isEmpty ? nil : 0
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            switch target {
            case .drawer(let id):
                if let drawer = model.drawer(id) {
                    MarkView(drawer.mark, size: 16)
                    Text(verbatim: drawer.name).font(.system(size: 13, weight: .semibold))
                }
            case .all:
                Image(nsImage: TiroirGlyph.image(.closed)).renderingMode(.template)
                Text(verbatim: Strings.allIcons).font(.system(size: 13, weight: .semibold))
            }
            Text(verbatim: Strings.iconCount(flatRows.count)).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if !filter.isEmpty {
                Label { Text(verbatim: filter) } icon: { Image(systemName: "line.3.horizontal.decrease") }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.selection))
                    .accessibilityLabel(Text(verbatim: Strings.filterLabel(filter)))
            }
            Button {
                if case .drawer(let id) = target { model.selectedDrawer = id }
                model.actions.openSettings(target == .all ? .layout : .drawers)
                onClose()
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(Strings.editThisDrawer)
            .accessibilityLabel(Text(verbatim: Strings.editThisDrawer))
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text(verbatim: target == .all ? Strings.noHiddenIcons : Strings.emptyDrawerTitle).font(.system(size: 12, weight: .medium))
            Text(verbatim: Strings.emptyDrawerHint).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    /// The drawer's icons; fewer icons than columns sit in the middle.
    private func grid(_ rows: [IconRow]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tileWidth), spacing: 6), count: max(1, min(rows.count, columns))), alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                let index = flatRows.firstIndex(of: row)
                IconTile(row: row, isSelected: index != nil && index == selection)
                    .onTapGesture { onOpen(row.id) }
                    .contextMenu { contextMenu(for: row) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for row: IconRow) -> some View {
        Button(Strings.open) { onOpen(row.id) }
        Menu(Strings.moveTo) {
            ForEach(model.settings.layout.drawers) { drawer in
                Button(drawer.name) { model.move(row.id, to: .drawer(drawer.id)) }
            }
            Divider()
            Button(Strings.keepInMenuBar) { model.move(row.id, to: .menuBar) }
            Button(Strings.hide) { model.move(row.id, to: .hidden) }
        }
        Divider()
        Button(Strings.showInFinder) { model.actions.showInFinder(row.id) }
    }

    /// One drawer of the chest: its mark and name, then its icons in a row that scrolls sideways when long.
    private func chestRow(_ section: (id: String, title: String?, mark: DrawerMark?, rows: [IconRow])) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                if let mark = section.mark { MarkView(mark, size: 16).frame(width: 22) }
                Text(verbatim: section.title ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(2)
            }
            .frame(width: Self.chestLabelWidth, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(section.rows) { row in
                        let index = flatRows.firstIndex(of: row)
                        IconTile(row: row, size: 28, isSelected: index != nil && index == selection, showsSubtitle: false)
                            .frame(width: Self.chestTileWidth)
                            .onTapGesture { onOpen(row.id) }
                            .contextMenu { contextMenu(for: row) }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    /// Up and down in the chest move to the first icon of the drawer above or below.
    private func jumpSection(_ delta: Int) -> KeyPress.Result {
        var offsets: [Int] = []
        var running = 0
        for section in sections {
            offsets.append(running)
            running += section.rows.count
        }
        guard running > 0 else { return .handled }
        let current = selection ?? 0
        let sectionIndex = offsets.lastIndex { $0 <= current } ?? 0
        var target = sectionIndex + delta
        while offsets.indices.contains(target), sections[target].rows.isEmpty { target += delta }
        if offsets.indices.contains(target) { selection = offsets[target] }
        return .handled
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        let count = flatRows.count
        guard count > 0 else { return .handled }
        let current = selection ?? (delta > 0 ? -1 : count)
        selection = min(max(current + delta, 0), count - 1)
        return .handled
    }
}

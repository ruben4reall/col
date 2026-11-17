import AppKit
import SwiftUI
import TiroirCore

/// One card of the arrangement board: the menu bar, a drawer, or Hidden.
public struct BoardSection: Identifiable {
    public var placement: Placement
    public var title: String
    public var subtitle: String?
    public var mark: DrawerMark?
    public var rows: [IconRow]

    public var id: String {
        switch placement {
        case .menuBar: "menuBar"
        case .hidden: "hidden"
        case .drawer(let id): id.uuidString
        }
    }

    public init(placement: Placement, title: String, subtitle: String? = nil, mark: DrawerMark? = nil, rows: [IconRow]) {
        self.placement = placement
        self.title = title
        self.subtitle = subtitle
        self.mark = mark
        self.rows = rows
    }
}

/// Cards of icons that can be dragged from one card to another: the welcome's Smart Sort step and Settings, Layout.
/// A right-click on an icon does the same without dragging (Move To), and more where the board allows it.
public struct ArrangementBoard: View {
    let sections: [BoardSection]
    let columns: Int
    let onDrop: (IconID, Placement) -> Void
    var onMarkTap: ((UUID) -> Void)?
    var lockReason: (IconRow) -> String? = { _ in nil }
    var onOpen: ((IconID) -> Void)?
    var onAddShortcut: ((IconID) -> Void)?

    public init(
        sections: [BoardSection], columns: Int = 2, onDrop: @escaping (IconID, Placement) -> Void,
        onMarkTap: ((UUID) -> Void)? = nil, lockReason: @escaping (IconRow) -> String? = { _ in nil },
        onOpen: ((IconID) -> Void)? = nil, onAddShortcut: ((IconID) -> Void)? = nil
    ) {
        self.sections = sections
        self.columns = columns
        self.onDrop = onDrop
        self.onMarkTap = onMarkTap
        self.lockReason = lockReason
        self.onOpen = onOpen
        self.onAddShortcut = onAddShortcut
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columns), spacing: 12) {
            ForEach(sections) { section in
                BoardCard(section: section, onDrop: onDrop, onMarkTap: onMarkTap, lockReason: lockReason, allRows: allRows,
                          destinations: sections.map { ($0.placement, $0.title) }, onOpen: onOpen, onAddShortcut: onAddShortcut)
            }
        }
    }

    private var allRows: [IconRow] { sections.flatMap(\.rows) }
}

struct BoardCard: View {
    let section: BoardSection
    let onDrop: (IconID, Placement) -> Void
    let onMarkTap: ((UUID) -> Void)?
    let lockReason: (IconRow) -> String?
    let allRows: [IconRow]
    /// Every card, for Move To.
    let destinations: [(placement: Placement, title: String)]
    let onOpen: ((IconID) -> Void)?
    let onAddShortcut: ((IconID) -> Void)?
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let mark = section.mark {
                    Button {
                        if case .drawer(let id) = section.placement { onMarkTap?(id) }
                    } label: {
                        MarkView(mark, size: 17)
                            .frame(width: 30, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .disabled(onMarkTap == nil || section.placement == .menuBar || section.placement == .hidden)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: section.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    if let subtitle = section.subtitle {
                        Text(verbatim: subtitle).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Text(verbatim: "\(section.rows.count)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.tertiaryText)
            }
            FlowLayout(spacing: 6) {
                ForEach(section.rows) { row in
                    chip(row)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(isTargeted ? Theme.selection : Theme.cardFill))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : Theme.cardStroke, lineWidth: isTargeted ? 1.5 : 1))
        .dropDestination(for: String.self) { items, _ in
            for item in items {
                if let row = allRows.first(where: { $0.id.description == item }), row.isMovable {
                    onDrop(row.id, section.placement)
                }
            }
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    @ViewBuilder
    private func chip(_ row: IconRow) -> some View {
        let reason = lockReason(row)
        let content = HStack(spacing: 6) {
            Image(nsImage: row.appIcon).resizable().interpolation(.high).frame(width: 18, height: 18)
                .opacity(row.isRunning ? 1 : 0.5)
            Text(verbatim: row.name).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(1)
            if reason != nil || !row.isMovable {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .help(reason ?? row.subtitle ?? row.appName)
        .contextMenu { chipMenu(row, movable: row.isMovable && reason == nil) }
        if row.isMovable && reason == nil {
            content.draggable(row.id.description) {
                HStack(spacing: 6) {
                    Image(nsImage: row.appIcon).resizable().frame(width: 20, height: 20)
                    Text(verbatim: row.name).font(.system(size: 12, weight: .medium))
                }
                .padding(6)
            }
        } else {
            content
        }
    }
}

extension BoardCard {
    @ViewBuilder
    func chipMenu(_ row: IconRow, movable: Bool) -> some View {
        if let onOpen {
            Button(Strings.open) { onOpen(row.id) }
        }
        if movable {
            Menu(Strings.moveTo) {
                ForEach(destinations.filter { $0.placement != section.placement }, id: \.placement) { destination in
                    Button(destination.title) { onDrop(row.id, destination.placement) }
                }
            }
        }
        if let onAddShortcut {
            Divider()
            Button(Strings.addShortcutMenuItem) { onAddShortcut(row.id) }
        }
    }
}

/// Lays chips out in rows, wrapping at the available width.
public struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

import AppKit
import SwiftUI
import TiroirCore

/// The menu bar's drawers in Col's island: a chip for each drawer, and the icons of the one chosen in a row below. A
/// click on an icon opens that icon's menu, as a click in the drawer would; the island closes first.
@available(macOS 26, *)
public struct IslandDrawersView: View {
    let model: InterfaceModel
    let accent: Color
    let onOpen: (IconID) -> Void
    let onSettings: () -> Void
    @State private var chosen: String?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: InterfaceModel, accent: Color, onOpen: @escaping (IconID) -> Void, onSettings: @escaping () -> Void) {
        self.model = model
        self.accent = accent
        self.onOpen = onOpen
        self.onSettings = onSettings
    }

    private struct Shelf: Identifiable {
        let id: String
        let name: String
        let mark: DrawerMark
        let rows: [IconRow]
    }

    /// The drawers in their order, then the icons hidden from the menu bar, when there are some.
    private var shelves: [Shelf] {
        var shelves = model.settings.layout.drawers.map { drawer in
            Shelf(id: drawer.id.uuidString, name: drawer.name, mark: drawer.mark, rows: model.members(of: drawer.id))
        }
        let hidden = model.hiddenRows
        if !hidden.isEmpty { shelves.append(Shelf(id: "hidden", name: Strings.hidden, mark: .symbol("eye.slash"), rows: hidden)) }
        return shelves
    }

    private var current: Shelf? {
        let all = shelves
        return all.first { $0.id == chosen } ?? all.first { !$0.rows.isEmpty } ?? all.first
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelves) { shelf in chip(shelf) }
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, TrailingFade.width)
                }
                .scrollEdgeEffectHidden(true, for: .horizontal)
                .mask { TrailingFade() }
                Button(action: onSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Strings.editThisDrawer)
                .accessibilityLabel(Text(verbatim: Strings.editThisDrawer))
            }
            if let current, !current.rows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(current.rows.enumerated()), id: \.element.id) { index, row in
                            tile(row)
                                .opacity(appeared || reduceMotion ? 1 : 0)
                                .offset(y: appeared || reduceMotion ? 0 : 6)
                                .animation(.spring(response: 0.34, dampingFraction: 0.82).delay(min(Double(index) * 0.018, 0.2)), value: appeared)
                        }
                    }
                    .padding(.trailing, TrailingFade.width)
                }
                .scrollEdgeEffectHidden(true, for: .horizontal)
                .mask { TrailingFade() }
                .id(current.id)
                .transition(.opacity)
            } else {
                Text(verbatim: shelves.isEmpty ? Strings.noHiddenIcons : Strings.emptyDrawerTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    private func chip(_ shelf: Shelf) -> some View {
        let isOn = shelf.id == current?.id
        return Button {
            withAnimation(.snappy(duration: 0.25)) { chosen = shelf.id }
        } label: {
            HStack(spacing: 5) {
                MarkView(shelf.mark, size: 12)
                Text(verbatim: shelf.name).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(verbatim: "\(shelf.rows.count)").font(.system(size: 10.5, weight: .semibold)).opacity(0.55)
            }
            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.75))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(isOn ? accent.opacity(0.9) : Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func tile(_ row: IconRow) -> some View {
        IslandIconTile(row: row) { onOpen(row.id) }
    }
}

/// A row that scrolls sideways fades out at its trailing edge: a chip or an icon the island's edge cuts reads as more
/// to come rather than as a mistake. The row ends with as much room, so its last item, scrolled to, shows whole.
@available(macOS 26, *)
private struct TrailingFade: View {
    static let width: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.width)
        }
    }
}

/// An icon of the menu bar in the island: the app's icon and the item's name, lit under the pointer.
@available(macOS 26, *)
private struct IslandIconTile: View {
    let row: IconRow
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(nsImage: row.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .opacity(row.isRunning ? 1 : 0.5)
                    .scaleEffect(hovering ? 1.08 : 1)
                Text(verbatim: row.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 66)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.1 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.snappy(duration: 0.2), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(row.subtitle.map { "\(row.name), \($0)" } ?? row.name)
        .accessibilityLabel(Text(verbatim: row.subtitle.map { "\(row.name), \($0)" } ?? row.name))
    }
}

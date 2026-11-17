import AppKit
import SwiftUI
import TiroirCore

/// Search (spec 6.2): a glass field under the menu bar. Two letters and Return open an icon's menu.
public struct SearchView: View {
    let model: InterfaceModel
    let onOpen: (IconID) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    static let maximumResults = 8

    public init(model: InterfaceModel, initialQuery: String = "", onOpen: @escaping (IconID) -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.onOpen = onOpen
        self.onClose = onClose
        _query = State(initialValue: initialQuery)
    }

    var results: [IconRow] {
        let items = model.icons.map { row in
            SearchItem(id: row.id, title: row.name, subtitle: row.label, drawerName: model.placeName(of: row))
        }
        let ranked = SearchRanker.rank(query, in: items).prefix(Self.maximumResults)
        return ranked.compactMap { model.row($0.id) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                TextField(Strings.searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular))
                    .focused($fieldFocused)
                    .onSubmit(openSelection)
                    .onChange(of: query) { selection = 0 }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            let rows = results
            if !query.isEmpty {
                Divider().opacity(0.5)
                if rows.isEmpty {
                    Text(verbatim: Strings.noSearchResult(query))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            resultRow(row, isSelected: index == selection)
                                .onTapGesture { onOpen(row.id) }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .onAppear { fieldFocused = true }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(results.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
    }

    private func resultRow(_ row: IconRow, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: row.appIcon).resizable().interpolation(.high).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.name).font(.system(size: 13, weight: .medium))
                if let subtitle = row.subtitle {
                    Text(verbatim: subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: model.placeName(of: row))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Theme.selection : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func openSelection() {
        let rows = results
        guard rows.indices.contains(selection) else { return }
        onOpen(rows[selection].id)
    }
}

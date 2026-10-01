import IsletCore
import SwiftUI

/// The pages of the open island: their order, and what each one holds. The stage above shows the real island on the
/// page being edited, and every change is saved and shows at once.
struct PagesPane: View {
    @State private var deck = Preferences.pageDeck
    @State private var selected = Preferences.pageDeck.pages[0].id

    var body: some View {
        PaneScaffold(pane: .pages) {
            Section {
                IslandStage(size: Preferences.islandSize, glass: IslandView.glassAvailable ? Preferences.islandGlass : .off,
                            deck: deck, page: selected)
                    .frame(height: IslandStage.height(for: Preferences.islandSize))
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("The page you are editing, on your own island.", bundle: .module)
            }
            Section {
                ForEach(Array(deck.pages.enumerated()), id: \.element.id) { index, page in
                    PageRow(page: page, selected: page.id == selected, first: index == 0, last: index == deck.pages.count - 1) {
                        selected = page.id
                    } move: { offset in
                        deck.move(page.id, by: offset)
                        save()
                    }
                }
                Button {
                    let page = deck.add([WidgetStack([.clock]), WidgetStack([.agenda])])
                    selected = page.id
                    save()
                } label: {
                    Label { Text("Add a Page", bundle: .module) } icon: { Image(systemName: "plus.circle.fill") }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Pages", bundle: .module)
            } footer: {
                Text("The tabs of the open island, in this order. Live joins them on the right of the camera while something runs.", bundle: .module)
            }
            if let page = deck.page(selected) {
                PageEditor(page: page, canDelete: deck.pages.count > 1) { edited in
                    deck.update(edited)
                    save()
                } delete: {
                    let index = deck.pages.firstIndex { $0.id == page.id } ?? 0
                    deck.remove(page.id)
                    selected = deck.pages[min(index, deck.pages.count - 1)].id
                    save()
                }
                .id(page.id)
            }
            Section {
                Button { deck = PageDeck.standard; selected = deck.pages[0].id; save() } label: {
                    Text("Restore the Original Pages", bundle: .module)
                }
            }
        }
    }

    private func save() {
        deck = deck.validated()
        Preferences.pageDeck = deck
        if deck.page(selected) == nil { selected = deck.pages[0].id }
    }
}

/// A page in the list: its tab, its name and what it holds.
private struct PageRow: View {
    let page: PageLayout
    let selected: Bool
    let first: Bool
    let last: Bool
    let select: () -> Void
    let move: (Int) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.tabSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: page.title)
                Text(verbatim: page.contents)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if hovering {
                HStack(spacing: 2) {
                    Button { move(-1) } label: { Image(systemName: "chevron.up") }
                        .disabled(first)
                        .help(Text("Move up", bundle: .module))
                    Button { move(1) } label: { Image(systemName: "chevron.down") }
                        .disabled(last)
                        .help(Text("Move down", bundle: .module))
                }
                .buttonStyle(.borderless)
                .transition(.opacity)
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .font(.system(size: selected ? 15 : 11, weight: .semibold))
                .frame(width: 18)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension PageLayout {
    /// What the page holds, place by place: "Music › Clock · Agenda", or what its only widget does.
    var contents: String {
        if widgets.count == 1 { return String(localized: widgets[0].summary) }
        return stacks.map { stack in stack.widgets.map { String(localized: $0.title) }.joined(separator: " › ") }.joined(separator: "  ·  ")
    }
}

/// The page being edited: its name, its tab, one wide place or two, and the widgets of each place.
private struct PageEditor: View {
    let page: PageLayout
    let canDelete: Bool
    let change: (PageLayout) -> Void
    let delete: () -> Void
    @State private var name: String

    init(page: PageLayout, canDelete: Bool, change: @escaping (PageLayout) -> Void, delete: @escaping () -> Void) {
        self.page = page
        self.canDelete = canDelete
        self.change = change
        self.delete = delete
        _name = State(initialValue: page.name ?? "")
    }

    static let symbols = [
        "house.fill", "music.note", "calendar", "clock.fill", "tray.full.fill", "doc.on.clipboard.fill",
        "square.grid.2x2.fill", "gauge.with.dots.needle.67percent", "star.fill", "heart.fill", "briefcase.fill", "sparkles",
        "bolt.fill", "leaf.fill", "book.fill", "gamecontroller.fill",
    ]

    var body: some View {
        Section {
            LabeledContent {
                TextField(text: $name, prompt: Text(verbatim: page.title)) { EmptyView() }
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .onSubmit(rename)
                    .onChange(of: name) { rename() }
            } label: {
                Text("Name", bundle: .module)
            }
            LabeledContent {
                HStack(spacing: 4) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            var edited = page
                            edited.symbol = symbol
                            change(edited)
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(page.tabSymbol == symbol ? .white : .secondary)
                                .frame(width: 24, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(page.tabSymbol == symbol ? Color.accentColor : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } label: {
                Text("Tab", bundle: .module)
            }
            Picker(selection: Binding(get: { page.stacks.count }, set: { count in
                var edited = page
                edited.setColumns(count)
                change(edited)
            })) {
                Text("One Wide Place", bundle: .module).tag(1)
                Text("Two Places", bundle: .module).tag(2)
            } label: {
                Text("Layout", bundle: .module)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(verbatim: page.title)
        }
        ForEach(Array(page.stacks.enumerated()), id: \.offset) { index, stack in
            StackEditor(stack: stack, width: page.width, title: placeTitle(index)) { edited in
                var page = page
                page.stacks[index] = edited
                change(page)
            }
        }
        if canDelete {
            Section {
                Button(role: .destructive, action: delete) { Text("Delete This Page", bundle: .module) }
            }
        }
    }

    private func placeTitle(_ index: Int) -> Text {
        page.stacks.count == 1
            ? Text("Across the page", bundle: .module)
            : (index == 0 ? Text("Left", bundle: .module) : Text("Right", bundle: .module))
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard (page.name ?? "") != trimmed else { return }
        var edited = page
        edited.name = trimmed.isEmpty ? nil : trimmed
        change(edited)
    }
}

/// One place of the page: its widgets in order, the first that has something to show being the one on show.
private struct StackEditor: View {
    let stack: WidgetStack
    let width: WidgetWidth
    let title: Text
    let change: (WidgetStack) -> Void

    var body: some View {
        Section {
            ForEach(Array(stack.widgets.enumerated()), id: \.element) { index, kind in
                HStack(spacing: 12) {
                    IconTile(symbol: kind.symbol, tint: kind.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                        Text(kind.summary).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 2) {
                        Button { move(kind, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                            .help(Text("Move up", bundle: .module))
                        Button { move(kind, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == stack.widgets.count - 1)
                            .help(Text("Move down", bundle: .module))
                        Button { remove(kind) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                            .disabled(stack.widgets.count == 1)
                            .help(Text("Remove", bundle: .module))
                    }
                    .buttonStyle(.borderless)
                }
            }
            let addable = WidgetKind.allCases.filter { $0.widths.contains(width) && !stack.widgets.contains($0) }
            if !addable.isEmpty {
                Menu {
                    ForEach(addable, id: \.self) { kind in
                        Button { change(WidgetStack(stack.widgets + [kind])) } label: {
                            Label { Text(kind.title) } icon: { Image(systemName: kind.symbol) }
                        }
                    }
                } label: {
                    Label { Text("Add a Widget", bundle: .module) } icon: { Image(systemName: "plus.circle.fill") }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } header: {
            title
        } footer: {
            if stack.widgets.count > 1 {
                Text("The island shows the first one that has something to show: here, \(String(localized: stack.widgets[0].title)) while it can, else the next.", bundle: .module)
            }
        }
    }

    private func move(_ kind: WidgetKind, by offset: Int) {
        guard let index = stack.widgets.firstIndex(of: kind) else { return }
        var widgets = stack.widgets
        let target = min(max(index + offset, 0), widgets.count - 1)
        widgets.swapAt(index, target)
        change(WidgetStack(widgets))
    }

    private func remove(_ kind: WidgetKind) {
        change(WidgetStack(stack.widgets.filter { $0 != kind }))
    }
}

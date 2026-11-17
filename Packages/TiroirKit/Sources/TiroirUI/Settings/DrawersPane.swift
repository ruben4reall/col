import AppKit
import SwiftUI
import TiroirCore

/// Settings, Drawers (spec 6.3): each drawer's name, mark, what the menu bar shows of it, its shortcut.
struct DrawersPane: View {
    @Bindable var model: InterfaceModel
    @State private var confirmingDelete: Drawer?

    var body: some View {
        if model.settings.layout.drawers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: Strings.noDrawersYet).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                Button(Strings.newDrawer) { _ = model.addDrawer() }.buttonStyle(PillButtonStyle(.primary))
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                list
                if let drawer = selected {
                    editor(drawer)
                }
            }
            .confirmationDialog(
                confirmingDelete.map { Strings.deleteDrawerQuestion($0.name) } ?? "",
                isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })
            ) {
                Button(Strings.delete, role: .destructive) {
                    if let drawer = confirmingDelete { model.removeDrawer(drawer.id) }
                    confirmingDelete = nil
                }
                Button(Strings.cancel, role: .cancel) { confirmingDelete = nil }
            }
        }
    }

    private var selected: Drawer? {
        model.selectedDrawer.flatMap(model.drawer) ?? model.settings.layout.drawers.first
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            List(selection: Binding(get: { selected?.id }, set: { model.selectedDrawer = $0 })) {
                ForEach(model.settings.layout.drawers) { drawer in
                    HStack(spacing: 10) {
                        MarkView(drawer.mark, size: 16).frame(width: 24)
                        Text(verbatim: drawer.name).lineLimit(1)
                        Spacer()
                        Text(verbatim: "\(model.members(of: drawer.id).count)").foregroundStyle(Theme.tertiaryText).font(.system(size: 11, design: .rounded))
                    }
                    .tag(drawer.id)
                }
                .onMove { source, destination in
                    model.update { settings in
                        settings.layout.drawers.move(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(width: 210, height: 300)
            .card(radius: Theme.radius)
            Button(Strings.newDrawer) { _ = model.addDrawer() }.buttonStyle(PillButtonStyle(.secondary))
        }
    }

    private func editor(_ drawer: Drawer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: Strings.name) {
                TextField(Strings.name, text: Binding(get: { drawer.name }, set: { name in
                    var changed = drawer
                    changed.name = name
                    model.updateDrawer(changed)
                }))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .padding(.vertical, 4)
            }
            SettingsGroup(title: Strings.mark) {
                MarkPicker(mark: Binding(get: { drawer.mark }, set: { mark in
                    var changed = drawer
                    changed.mark = mark
                    model.updateDrawer(changed)
                }))
                .padding(.vertical, 6)
                .id(drawer.id)
            }
            SettingsGroup {
                SettingRow(title: Strings.showNameInMenuBar) {
                    Toggle(Strings.showNameInMenuBar, isOn: binding(drawer, \.showsName)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.showCount) {
                    Toggle(Strings.showCount, isOn: binding(drawer, \.showsCount)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.shortcut) {
                    ShortcutRecorder(shortcut: Binding(get: { drawer.shortcut }, set: { shortcut in
                        var changed = drawer
                        changed.shortcut = shortcut
                        model.updateDrawer(changed)
                    }), problem: model.refusedShortcuts.contains(drawer.id.uuidString) ? Strings.shortcutTaken : nil)
                }
            }
            Button(Strings.deleteDrawer) { confirmingDelete = drawer }.buttonStyle(PillButtonStyle(.destructive))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(_ drawer: Drawer, _ keyPath: WritableKeyPath<Drawer, Bool>) -> Binding<Bool> {
        Binding(get: { drawer[keyPath: keyPath] }, set: { value in
            var changed = drawer
            changed[keyPath: keyPath] = value
            model.updateDrawer(changed)
        })
    }
}

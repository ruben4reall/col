import AppKit
import SwiftUI
import TiroirCore
import TiroirSystem

/// Settings, Layout (spec 6.3): the menu bar as it is, the room left beside the notch, and the cards to drag icons
/// between.
struct LayoutPane: View {
    @Bindable var model: InterfaceModel
    @State private var editingMark: UUID?
    @State private var showingSmartSort = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: Strings.layoutSubtitle).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            MenuBarPreview(model: model)
            RoomGauge(model: model)
            HStack(spacing: 10) {
                Button(Strings.smartSortButton) { showingSmartSort = true }.buttonStyle(PillButtonStyle(.secondary))
                Button(Strings.newDrawer) { _ = model.addDrawer() }.buttonStyle(PillButtonStyle(.secondary))
                Spacer()
                if model.isApplying { ProgressView().controlSize(.small) }
            }
            if !model.failedMoves.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.failedMoves, id: \.self) { id in
                        Text(verbatim: Strings.couldNotMoveIcon(model.row(id)?.name ?? id.bundleID))
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.warning)
            }
            ForEach(Array(model.conflicts).sorted(), id: \.self) { bundleID in
                Text(verbatim: Strings.mixedAppOn27(model.icons.first { $0.id.bundleID == bundleID }?.appName ?? bundleID))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            ArrangementBoard(sections: sections, columns: 2, onDrop: { id, placement in
                model.move(id, to: placement)
            }, onMarkTap: { editingMark = $0 }, lockReason: lockReason, onOpen: { id in
                model.actions.openIcon(id, nil)
            }, onAddShortcut: { id in
                model.pendingIconShortcut = id
                model.settingsPane = .shortcuts
            })
        }
        .popover(item: Binding(get: { editingMark.map(DrawerEditing.init) }, set: { editingMark = $0?.id })) { editing in
            if let drawer = model.drawer(editing.id) {
                MarkPicker(mark: Binding(get: { drawer.mark }, set: { mark in
                    var changed = drawer
                    changed.mark = mark
                    model.updateDrawer(changed)
                }))
                .padding(16)
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showingSmartSort) {
            SmartSortSheet(model: model, isPresented: $showingSmartSort)
        }
    }

    private var sections: [BoardSection] {
        var result: [BoardSection] = [
            BoardSection(placement: .menuBar, title: Strings.menuBar, subtitle: Strings.menuBarSubtitle, mark: .symbol("menubar.rectangle"), rows: model.menuBarRows),
        ]
        for drawer in model.settings.layout.drawers {
            result.append(BoardSection(placement: .drawer(drawer.id), title: drawer.name, mark: drawer.mark, rows: model.members(of: drawer.id)))
        }
        result.append(BoardSection(placement: .hidden, title: Strings.hidden, subtitle: Strings.hiddenSubtitle, mark: .symbol("eye.slash"), rows: model.hiddenRows))
        return result
    }

    private func lockReason(_ row: IconRow) -> String? {
        if !row.isMovable {
            return row.kind == .system && model.engineKind == .goldenGate && !IconIdentity.fixedSystemIdentifiers.contains(row.id.key)
                ? Strings.appleIconsStayOn27 : Strings.fixedByMacOS
        }
        return nil
    }
}

private struct DrawerEditing: Identifiable {
    let id: UUID
}

/// The menu bar as it stands: the icons that show, Tiroir's drawers, and the notch when there is one.
struct MenuBarPreview: View {
    let model: InterfaceModel

    var body: some View {
        HStack(spacing: 0) {
            if model.hasNotch {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black).frame(width: 110, height: 30)
                    .overlay(Circle().fill(Color.white.opacity(0.08)).frame(width: 6, height: 6))
            }
            Spacer(minLength: 12)
            HStack(spacing: 12) {
                ForEach(model.settings.layout.drawers) { drawer in
                    MarkView(drawer.mark, size: 15)
                        .help(drawer.name)
                }
                if model.settings.behavior.showsTiroirIcon {
                    Image(nsImage: TiroirGlyph.image(.closed)).renderingMode(.template).foregroundStyle(Theme.text)
                }
                ForEach(model.menuBarRows.filter(\.isMovable).reversed()) { row in
                    Group {
                        if row.kind == .system {
                            Image(systemName: SystemIcons.symbol(for: row.id)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                        } else {
                            Image(nsImage: row.appIcon).resizable().interpolation(.high)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .help(row.name)
                }
                ForEach(model.menuBarRows.filter { !$0.isMovable }.reversed()) { row in
                    Image(systemName: SystemIcons.symbol(for: row.id)).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 18, height: 18)
                        .help(row.name)
                }
            }
            .padding(.trailing, 14)
        }
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
        .accessibilityHidden(true)
    }
}

/// How much of the room beside the notch the icons take (spec 6.4).
struct RoomGauge: View {
    let model: InterfaceModel

    var body: some View {
        if let capacity = model.capacity {
            VStack(alignment: .leading, spacing: 8) {
                // The gauge reads as one sentence; the controls under it stay separate.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(verbatim: model.hasNotch ? Strings.roomBesideNotch : Strings.roomInMenuBar).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(verbatim: Strings.roomUsed(Int(capacity.used.rounded()), of: Int(capacity.room.rounded())))
                            .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.secondaryText)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(capacity.fits ? AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Theme.warning))
                                .frame(width: proxy.size.width * min(capacity.share, 1))
                        }
                    }
                    .frame(height: 8)
                }
                .accessibilityElement(children: .combine)
                if !capacity.fits {
                    HStack {
                        Text(verbatim: Strings.iconsDoNotFit(capacity.overflow.count)).font(.system(size: 12)).foregroundStyle(Theme.warning)
                        Spacer()
                        Button(Strings.moveThemToDrawer) { model.moveOverflowIntoDrawer() }.buttonStyle(PillButtonStyle(.primary))
                    }
                }
                Divider().opacity(0.4)
                if model.engineKind != .goldenGate {
                    SettingRow(title: Strings.iconSpacingRow,
                               note: model.iconSpacingChanged ? Strings.iconSpacingPending : Strings.iconSpacingNote) {
                        Picker(Strings.iconSpacingRow, selection: Binding(get: { model.iconSpacing }, set: { model.actions.setIconSpacing($0) })) {
                            Text(verbatim: Strings.spacingStandard).tag(IconSpacing.standard)
                            Text(verbatim: Strings.spacingSnug).tag(IconSpacing.snug)
                            Text(verbatim: Strings.spacingCompact).tag(IconSpacing.compact)
                            Text(verbatim: Strings.spacingTight).tag(IconSpacing.tight)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingRow(title: Strings.moveOverflowAutomatically, note: Strings.moveOverflowAutomaticallyNote) {
                    Toggle(Strings.moveOverflowAutomatically, isOn: Binding(get: { model.settings.behavior.movesOverflowAutomatically }, set: { value in
                        model.update { $0.behavior.movesOverflowAutomatically = value }
                    }))
                    .labelsHidden().toggleStyle(.switch)
                }
            }
            .padding(14)
            .card(radius: Theme.radius)
        }
    }
}

/// Smart Sort again, from Settings: the same proposal as the welcome, applied on confirmation.
struct SmartSortSheet: View {
    let model: InterfaceModel
    @Binding var isPresented: Bool
    @State private var welcome = WelcomeModel(step: .sort)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: Strings.smartSortTitle).font(.system(size: 20, weight: .semibold))
            Picker(Strings.smartSortTitle, selection: $welcome.strategy) {
                Text(verbatim: Strings.byPurpose).tag(SortStrategy.purpose)
                Text(verbatim: Strings.byDeveloper).tag(SortStrategy.developer)
                Text(verbatim: Strings.oneDrawer).tag(SortStrategy.justOne)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            .onChange(of: welcome.strategy) { _, strategy in welcome.proposal = model.actions.propose(strategy) }
            ScrollView {
                ArrangementBoard(sections: sections, columns: 2) { id, placement in welcome.proposal.assign(id, to: placement) }
                    .padding(.bottom, 18)
            }
            .frame(height: 380)
            .mask { ScrollFade() }
            HStack {
                Text(verbatim: Strings.iconsLeaveMenuBar(welcome.leavingCount(in: model))).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button(Strings.cancel) { isPresented = false }.buttonStyle(PillButtonStyle(.secondary)).keyboardShortcut(.cancelAction)
                Button(Strings.sortMyMenuBar) {
                    let layout = welcome.proposal, strategy = welcome.strategy
                    isPresented = false
                    Task { _ = await model.actions.applySmartSort(layout, strategy) }
                }
                .buttonStyle(PillButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .onAppear { welcome.proposal = model.actions.propose(welcome.strategy) }
    }

    private var sections: [BoardSection] {
        var result = welcome.proposal.drawers.map { drawer in
            BoardSection(placement: .drawer(drawer.id), title: drawer.name, mark: drawer.mark, rows: welcome.members(of: drawer.id, in: model))
        }
        result.insert(BoardSection(placement: .menuBar, title: Strings.menuBar, mark: .symbol("menubar.rectangle"), rows: welcome.menuBarRows(in: model)), at: 0)
        return result
    }
}

import AppKit
import SwiftUI
import TiroirCore
import TiroirSystem

/// The welcome window's content (spec 6.1): hello, one permission, Smart Sort, ready. Under a minute.
public struct WelcomeView: View {
    let model: InterfaceModel
    @Bindable var welcome: WelcomeModel
    let onFinish: () -> Void
    @State private var editingMark: UUID?

    public init(model: InterfaceModel, welcome: WelcomeModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.welcome = welcome
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch welcome.step {
                case .hello: hello
                case .permission: permission
                case .sort: sort
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(width: 680, height: 600)
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .animation(.easeInOut(duration: 0.22), value: welcome.step)
    }

    // MARK: Steps

    private var hello: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            SortingPicture()
            VStack(spacing: 10) {
                Text(verbatim: Strings.welcomeTitle).font(.system(size: 30, weight: .semibold))
                Text(verbatim: Strings.welcomeBody)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            Spacer(minLength: 0)
        }
    }

    private var permission: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: model.accessibilityTrusted ? "checkmark.circle.fill" : "hand.raised.fill")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(model.accessibilityTrusted ? Color.green : Theme.accent)
                .contentTransition(.symbolEffect(.replace))
            VStack(spacing: 10) {
                Text(verbatim: Strings.permissionTitle).font(.system(size: 26, weight: .semibold))
                Text(verbatim: Strings.permissionBody)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            HStack(spacing: 8) {
                Image(systemName: model.accessibilityTrusted ? "checkmark" : "hourglass")
                Text(verbatim: model.accessibilityTrusted ? Strings.permissionGranted : Strings.permissionWaiting)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(model.accessibilityTrusted ? Color.green : Theme.secondaryText)
            if !model.accessibilityTrusted {
                Button(Strings.openSystemSettings) {
                    model.actions.requestAccessibility()
                    model.actions.openAccessibilitySettings()
                }
                .buttonStyle(PillButtonStyle(.primary))
                Text(verbatim: Strings.permissionSteps).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
            }
            if model.engineKind == .goldenGate, !model.isInApplications {
                VStack(spacing: 8) {
                    Text(verbatim: Strings.applicationsFolderNote).font(.system(size: 12)).foregroundStyle(Theme.warning)
                    Button(Strings.moveToApplications) { model.actions.moveToApplications() }
                        .buttonStyle(PillButtonStyle(.secondary))
                }
            } else if model.engineKind == .tahoe {
                Text(verbatim: Strings.tahoePointerNote)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Spacer(minLength: 0)
        }
    }

    private var sort: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: Strings.smartSortTitle).font(.system(size: 26, weight: .semibold))
                Text(verbatim: model.icons.isEmpty ? Strings.noIconsFound : Strings.smartSortFound(model.icons.count))
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
            if !model.icons.isEmpty {
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
                    ArrangementBoard(sections: sections, columns: 2, onDrop: { id, placement in
                        welcome.proposal.assign(id, to: placement)
                    }, onMarkTap: { editingMark = $0 })
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.never)
                .mask { ScrollFade() }
                HStack(spacing: 10) {
                    Text(verbatim: Strings.smartSortHint).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    Text(verbatim: Strings.iconsLeaveMenuBar(welcome.leavingCount(in: model)))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                }
                if let report = welcome.report, !report.failed.isEmpty {
                    Text(verbatim: Strings.couldNotMove(count: report.failed.count)).font(.system(size: 12)).foregroundStyle(Theme.warning)
                }
            }
        }
        .popover(item: Binding(get: { editingMark.map(MarkEditing.init) }, set: { editingMark = $0?.id })) { editing in
            if let drawer = welcome.proposal.drawer(editing.id) {
                MarkPicker(mark: Binding(get: { drawer.mark }, set: { mark in
                    var changed = drawer
                    changed.mark = mark
                    welcome.proposal.updateDrawer(changed)
                }))
                .padding(16)
                .preferredColorScheme(.dark)
            }
        }
        .onAppear {
            if welcome.proposal.drawers.isEmpty { welcome.proposal = model.actions.propose(welcome.strategy) }
        }
    }

    private var sections: [BoardSection] {
        var result = welcome.proposal.drawers.map { drawer in
            BoardSection(placement: .drawer(drawer.id), title: drawer.name, mark: drawer.mark, rows: welcome.members(of: drawer.id, in: model))
        }
        result.insert(BoardSection(placement: .menuBar, title: Strings.menuBar, subtitle: Strings.menuBarSubtitle,
                                   mark: .symbol("menubar.rectangle"), rows: welcome.menuBarRows(in: model)), at: 0)
        return result
    }

    private var ready: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            VStack(spacing: 10) {
                Text(verbatim: Strings.readyTitle).font(.system(size: 30, weight: .semibold))
                Text(verbatim: model.settings.shortcuts.search.map { Strings.readyBody(search: $0.display) } ?? Strings.readyBodyWithoutShortcut)
                    .font(.system(size: 15)).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            VStack(alignment: .leading, spacing: 10) {
                Toggle(Strings.openAtLogin, isOn: $welcome.openAtLogin)
                Toggle(Strings.keepUpToDate, isOn: $welcome.keepUpToDate)
            }
            .toggleStyle(.switch)
            .font(.system(size: 13))
            .padding(16)
            .card()
            Spacer(minLength: 0)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(WelcomeModel.Step.allCases, id: \.self) { step in
                    Circle().fill(step == welcome.step ? Theme.accent : Color.white.opacity(0.18)).frame(width: 6, height: 6)
                }
            }
            Spacer()
            if welcome.step != .hello, welcome.step != .ready {
                Button(Strings.back) { welcome.previous() }.buttonStyle(PillButtonStyle(.secondary))
            }
            switch welcome.step {
            case .hello:
                Button(Strings.continueButton) { welcome.next() }.buttonStyle(PillButtonStyle(.primary)).keyboardShortcut(.defaultAction)
            case .permission:
                Button(model.accessibilityTrusted ? Strings.continueButton : Strings.skipForNow) { welcome.next() }
                    .buttonStyle(PillButtonStyle(model.accessibilityTrusted ? .primary : .secondary))
                    .keyboardShortcut(.defaultAction)
            case .sort:
                if welcome.isSorting {
                    ProgressView().controlSize(.small)
                    Text(verbatim: model.applyProgress.map { "\($0.done) / \($0.total)" } ?? Strings.sorting)
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                } else if model.icons.isEmpty {
                    Button(Strings.continueButton) { welcome.next() }.buttonStyle(PillButtonStyle(.primary))
                } else {
                    Button(Strings.startEmpty) { welcome.next() }.buttonStyle(PillButtonStyle(.secondary))
                    Button(Strings.sortMyMenuBar) {
                        welcome.isSorting = true
                        Task {
                            welcome.report = await model.actions.applySmartSort(welcome.proposal, welcome.strategy)
                            welcome.isSorting = false
                            if welcome.report?.failed.isEmpty ?? true { welcome.next() }
                        }
                    }
                    .buttonStyle(PillButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.accessibilityTrusted && model.engineKind != .demo)
                }
            case .ready:
                Button(Strings.done) {
                    model.actions.setOpenAtLogin(welcome.openAtLogin)
                    model.actions.setAutomaticUpdates(welcome.keepUpToDate)
                    onFinish()
                }
                .buttonStyle(PillButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(height: 34)
    }
}

private struct MarkEditing: Identifiable {
    let id: UUID
}

/// The welcome's first picture: a crowded row of generic icons that folds into three drawers. It plays once, only
/// while the welcome is on screen.
struct SortingPicture: View {
    @State private var sorted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let glyphs = ["cloud.fill", "lock.fill", "bubble.left.fill", "key.fill", "envelope.fill", "photo.fill",
                         "shippingbox.fill", "sparkles", "terminal.fill", "waveform"]
    static let drawers = ["cloud.fill", "lock.fill", "bubble.left.and.bubble.right.fill"]

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            HStack(spacing: 14) {
                ZStack(alignment: .trailing) {
                    HStack(spacing: 13) {
                        ForEach(Self.glyphs, id: \.self) { name in
                            Image(systemName: name).font(.system(size: 15, weight: .medium))
                        }
                    }
                    .opacity(sorted ? 0 : 1)
                    .scaleEffect(sorted ? 0.6 : 1, anchor: .trailing)
                    .offset(x: sorted ? 40 : 0)
                    HStack(spacing: 16) {
                        ForEach(Self.drawers, id: \.self) { name in
                            Image(systemName: name).font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .opacity(sorted ? 1 : 0)
                    .scaleEffect(sorted ? 1 : 0.7, anchor: .trailing)
                }
                Image(systemName: "wifi").font(.system(size: 14, weight: .semibold))
                Image(systemName: "battery.75percent").font(.system(size: 15, weight: .regular))
                Text(verbatim: "9:41").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
        }
        .frame(width: 520, height: 44)
        .task {
            guard !reduceMotion else {
                sorted = true
                return
            }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { sorted = true }
        }
    }
}

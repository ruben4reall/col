import AppKit
import SwiftUI
import TiroirCore
import TiroirSystem

/// Settings, Behavior (spec 6.3).
struct BehaviorPane: View {
    @Bindable var model: InterfaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: Strings.newIcons) {
                Picker(Strings.newIcons, selection: Binding(get: { model.settings.layout.newIconPolicy }, set: { value in
                    model.update { $0.layout.newIconPolicy = value }
                })) {
                    Text(verbatim: Strings.sortIntoTheirDrawer).tag(NewIconPolicy.sortIntoDrawer)
                    Text(verbatim: Strings.showInMenuBar).tag(NewIconPolicy.menuBar)
                    Text(verbatim: Strings.hideNewIcons).tag(NewIconPolicy.hidden)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(.vertical, 6)
            }
            SettingsGroup {
                SettingRow(title: Strings.openOnHover) {
                    Toggle(Strings.openOnHover, isOn: behavior(\.opensOnHover)).labelsHidden().toggleStyle(.switch)
                }
                if model.settings.behavior.opensOnHover {
                    SettingRow(title: Strings.hoverDelay) {
                        HStack {
                            Slider(value: behavior(\.hoverDelay), in: Behavior.hoverDelayRange).frame(width: 180).accessibilityLabel(Text(verbatim: Strings.hoverDelay))
                            Text(verbatim: Strings.seconds(model.settings.behavior.hoverDelay.formatted(.number.precision(.fractionLength(0...2))))).monospacedDigit().frame(width: 44)
                        }
                    }
                }
                SettingRow(title: Strings.returnIconsAfter, note: Strings.returnIconsNote) {
                    HStack {
                        Slider(value: behavior(\.rehideDelay), in: 0...5, step: 0.5).frame(width: 180).accessibilityLabel(Text(verbatim: Strings.returnIconsAfter))
                        Text(verbatim: Strings.seconds(model.settings.behavior.rehideDelay.formatted(.number.precision(.fractionLength(1))))).monospacedDigit().frame(width: 44)
                    }
                }
                SettingRow(title: Strings.showTiroirIcon, note: Strings.showTiroirIconNote) {
                    Toggle(Strings.showTiroirIcon, isOn: behavior(\.showsTiroirIcon)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.keepItemsAtRightEnd, note: Strings.keepItemsAtRightEndNote) {
                    Toggle(Strings.keepItemsAtRightEnd, isOn: behavior(\.keepsItemsAtRightEnd)).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: Strings.revealSection) {
                SettingRow(title: Strings.optionClickShowsEverything) {
                    Toggle(Strings.optionClickShowsEverything, isOn: behavior(\.showsEverythingWithOption)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.revealOnHover) {
                    Toggle(Strings.revealOnHover, isOn: behavior(\.revealsOnHover)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.revealOnClick, note: Strings.revealEmptyNote) {
                    Toggle(Strings.revealOnClick, isOn: behavior(\.revealsOnClick)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.revealOnScroll, note: Strings.revealOnScrollNote) {
                    Toggle(Strings.revealOnScroll, isOn: behavior(\.revealsOnScroll)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.revealPlace, note: model.hasNotch ? Strings.revealPlaceNotchNote : nil) {
                    Picker(Strings.revealPlace, selection: behavior(\.revealPlace)) {
                        Text(verbatim: Strings.revealInMenuBar).tag(Behavior.RevealPlace.menuBar)
                        Text(verbatim: Strings.revealInAllDrawer).tag(Behavior.RevealPlace.allDrawer)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingRow(title: Strings.hideAgainAutomatically, note: Strings.hideAgainNote) {
                    Toggle(Strings.hideAgainAutomatically, isOn: behavior(\.hidesAgainAutomatically)).labelsHidden().toggleStyle(.switch)
                }
                if model.settings.behavior.hidesAgainAutomatically {
                    SettingRow(title: Strings.hoverDelay) {
                        HStack {
                            Slider(value: behavior(\.hideAgainDelay), in: Behavior.hideAgainDelayRange, step: 1).frame(width: 180).accessibilityLabel(Text(verbatim: Strings.hideAgainAutomatically))
                            Text(verbatim: Strings.seconds(model.settings.behavior.hideAgainDelay.formatted(.number.precision(.fractionLength(0))))).monospacedDigit().frame(width: 44)
                        }
                    }
                }
            }
            SettingsGroup(title: Strings.engine) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(verbatim: engineDescription).font(.system(size: 13))
                        if model.engineKind == .goldenGate {
                            Text(verbatim: Strings.beta).font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.selection))
                        }
                    }
                    if model.engineKind == .goldenGate {
                        Text(verbatim: Strings.goldenGateSideEffects).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var engineDescription: String {
        switch model.engineKind {
        case .tahoe: Strings.engineTahoe
        case .goldenGate: Strings.engineGoldenGate
        case .demo: Strings.engineDemo
        }
    }

    private func behavior<Value>(_ keyPath: WritableKeyPath<Behavior, Value>) -> Binding<Value> {
        Binding(get: { model.settings.behavior[keyPath: keyPath] }, set: { value in
            model.update { $0.behavior[keyPath: keyPath] = value }
        })
    }
}

/// Settings, Shortcuts (spec 6.3): Tiroir's own shortcuts, then one per icon.
struct ShortcutsPane: View {
    @Bindable var model: InterfaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup {
                SettingRow(title: Strings.searchIconsShortcut) {
                    ShortcutRecorder(shortcut: shortcut(\.search), problem: problem("search"))
                }
                SettingRow(title: Strings.openAllDrawers) {
                    ShortcutRecorder(shortcut: shortcut(\.allDrawer), problem: problem("allDrawer"))
                }
                SettingRow(title: Strings.showEveryIconShortcut, note: Strings.showEveryIconShortcutNote) {
                    ShortcutRecorder(shortcut: shortcut(\.showEverything), problem: problem("showEverything"))
                }
                SettingRow(title: Strings.focusShortcut, note: Strings.focusShortcutNote) {
                    ShortcutRecorder(shortcut: shortcut(\.focus), problem: problem("focus"))
                }
            }
            SettingsGroup(title: Strings.iconShortcutsSection) {
                Text(verbatim: Strings.iconShortcutsNote).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                    .padding(.vertical, 4)
                if iconRows.isEmpty {
                    Text(verbatim: Strings.noIconShortcuts).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        .padding(.vertical, 6)
                }
                ForEach(iconRows) { row in
                    HStack(spacing: 10) {
                        Image(nsImage: row.appIcon).resizable().interpolation(.high).frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: row.name).font(.system(size: 13)).lineLimit(1)
                            Text(verbatim: model.placeName(of: row)).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                        }
                        Spacer(minLength: 12)
                        ShortcutRecorder(shortcut: iconShortcut(row.id), problem: problem("icon:\(row.id.description)"),
                                         startsRecording: model.pendingIconShortcut == row.id)
                    }
                    .padding(.vertical, 5)
                }
                Menu {
                    ForEach(model.icons.filter { $0.isMovable && model.settings.shortcuts.shortcut(for: $0.id) == nil && $0.id != model.pendingIconShortcut }) { row in
                        Button(row.name) { model.pendingIconShortcut = row.id }
                    }
                } label: {
                    Text(verbatim: Strings.addIconShortcut)
                }
                .menuStyle(.button)
                .buttonStyle(PillButtonStyle(.secondary))
                .fixedSize()
                .padding(.vertical, 6)
                .disabled(model.icons.isEmpty)
            }
        }
    }

    /// Icons with a shortcut, then the one waiting for its keys.
    private var iconRows: [IconRow] {
        var rows = model.settings.shortcuts.icons.compactMap { model.row($0.icon) }
        if let pending = model.pendingIconShortcut, !rows.contains(where: { $0.id == pending }), let row = model.row(pending) {
            rows.append(row)
        }
        return rows
    }

    private func shortcut(_ keyPath: WritableKeyPath<Shortcuts, Shortcut?>) -> Binding<Shortcut?> {
        Binding(get: { model.settings.shortcuts[keyPath: keyPath] }, set: { value in
            model.update { $0.shortcuts[keyPath: keyPath] = value }
        })
    }

    private func iconShortcut(_ id: IconID) -> Binding<Shortcut?> {
        Binding(get: { model.settings.shortcuts.shortcut(for: id) }, set: { value in
            if model.pendingIconShortcut == id { model.pendingIconShortcut = nil }
            model.update { $0.shortcuts.setShortcut(value, for: id) }
        })
    }

    private func problem(_ key: String) -> String? {
        model.refusedShortcuts.contains(key) ? Strings.shortcutTaken : nil
    }
}

/// Settings, General (spec 6.3).
struct GeneralPane: View {
    @Bindable var model: InterfaceModel
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup {
                SettingRow(title: Strings.openAtLogin, note: model.loginItemStatus == .needsApproval ? Strings.loginNeedsApproval : nil) {
                    Toggle(Strings.openAtLogin, isOn: Binding(get: { model.loginItemStatus == .enabled || model.loginItemStatus == .needsApproval },
                                             set: { model.actions.setOpenAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.accessibility) {
                    HStack(spacing: 10) {
                        Text(verbatim: model.accessibilityTrusted ? Strings.on : Strings.off)
                            .foregroundStyle(model.accessibilityTrusted ? Color.green : Theme.warning)
                        if !model.accessibilityTrusted {
                            Button(Strings.openSystemSettings) {
                                model.actions.requestAccessibility()
                                model.actions.openAccessibilitySettings()
                            }
                            .buttonStyle(PillButtonStyle(.primary))
                        }
                    }
                }
                SettingRow(title: Strings.memory) {
                    Text(verbatim: model.memoryBytes.map { Strings.memoryInUse(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory)) } ?? "")
                        .monospacedDigit().foregroundStyle(Theme.secondaryText)
                }
            }
            SettingsGroup(title: Strings.updates) {
                SettingRow(title: Strings.checkAutomatically) {
                    Toggle(Strings.checkAutomatically, isOn: Binding(get: { model.automaticUpdates }, set: { model.actions.setAutomaticUpdates($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.version(model.appVersion)) {
                    Button(Strings.checkNow) { model.actions.checkForUpdates() }
                        .buttonStyle(PillButtonStyle(.secondary))
                        .disabled(!model.canCheckForUpdates)
                }
            }
            SettingsGroup(title: Strings.settingsFileSection) {
                SettingRow(title: Strings.settingsFileRow, note: Strings.settingsFileNote) {
                    HStack(spacing: 8) {
                        Button(Strings.exportSettings) { model.actions.exportSettings() }.buttonStyle(PillButtonStyle(.secondary))
                        Button(Strings.importSettings) { model.actions.importSettings() }.buttonStyle(PillButtonStyle(.secondary))
                    }
                }
            }
            SettingsGroup(title: Strings.helpSection) {
                SettingRow(title: Strings.pauseTiroir) {
                    Toggle(Strings.pauseTiroir, isOn: Binding(get: { model.isShowingEverything }, set: { _ in model.actions.toggleShowEverything() }))
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.reportProblemRow, note: Strings.diagnosticsNote) {
                    Button(Strings.copyDiagnostics) { model.actions.copyDiagnostics() }.buttonStyle(PillButtonStyle(.secondary))
                }
                SettingRow(title: Strings.welcomeRow, note: Strings.welcomeRowNote) {
                    Button(Strings.showAgain) { model.actions.showWelcomeAgain() }.buttonStyle(PillButtonStyle(.secondary))
                }
            }
            HStack(spacing: 10) {
                Button(Strings.resetLayout) { confirmingReset = true }.buttonStyle(PillButtonStyle(.destructive))
                Spacer()
                Button(Strings.quitTiroir) { model.actions.quit() }.buttonStyle(PillButtonStyle(.secondary))
            }
        }
        .confirmationDialog(Strings.resetLayoutQuestion, isPresented: $confirmingReset) {
            Button(Strings.reset, role: .destructive) { model.actions.resetLayout() }
            Button(Strings.cancel, role: .cancel) {}
        }
        .task {
            while !Task.isCancelled {
                model.actions.refreshMemory()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Settings, About (spec 6.3).
struct AboutPane: View {
    let model: InterfaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: Strings.appName).font(.system(size: 22, weight: .semibold))
                    Text(verbatim: Strings.tagline).foregroundStyle(Theme.secondaryText)
                    Text(verbatim: Strings.version(model.appVersion)).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                }
            }
            Text(verbatim: Strings.freeAndOpenSource).font(.system(size: 13))
            HStack(spacing: 10) {
                Link(Strings.website, destination: TiroirInfo.website)
                Link(Strings.sourceCode, destination: TiroirInfo.repository)
                Link(Strings.reportIssue, destination: TiroirInfo.issues)
            }
            .font(.system(size: 13, weight: .medium))
            Text(verbatim: Strings.creditsLine).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
            Text(verbatim: Strings.notAffiliated).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

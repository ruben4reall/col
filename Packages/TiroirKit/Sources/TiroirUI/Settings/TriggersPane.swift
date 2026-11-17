import AppKit
import SwiftUI
import TiroirCore

/// Settings, Triggers: each trigger reads as a sentence on a card, with its switch, and a mark while its condition
/// holds. With none yet, a sentence and a few examples to add in one click.
struct TriggersPane: View {
    @Bindable var model: InterfaceModel
    @State private var editing: TriggerDraft?
    @State private var confirmingDelete: Trigger?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.settings.triggers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: Strings.noTriggersYet).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(TriggerExample.examples(in: model)) { example in
                            Button {
                                model.saveTrigger(example.trigger)
                            } label: {
                                Label { Text(verbatim: example.title) } icon: { Image(systemName: example.symbol) }
                            }
                            .buttonStyle(PillButtonStyle(.secondary))
                        }
                    }
                    Button(Strings.addTrigger) { editing = TriggerDraft(in: model.settings) }.buttonStyle(PillButtonStyle(.primary))
                }
            } else {
                Text(verbatim: Strings.triggersSubtitle).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.settings.triggers) { trigger in
                        card(trigger)
                    }
                }
                Button(Strings.addTrigger) { editing = TriggerDraft(in: model.settings) }.buttonStyle(PillButtonStyle(.secondary))
            }
        }
        .sheet(item: $editing) { draft in
            TriggerEditor(model: model, draft: draft, onSave: { trigger in
                model.saveTrigger(trigger)
                editing = nil
            }, onCancel: { editing = nil })
        }
        .confirmationDialog(
            Strings.deleteTriggerQuestion,
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            presenting: confirmingDelete
        ) { trigger in
            Button(Strings.delete, role: .destructive) {
                model.removeTrigger(trigger.id)
                confirmingDelete = nil
            }
            Button(Strings.cancel, role: .cancel) { confirmingDelete = nil }
        } message: { trigger in
            Text(verbatim: TriggerText.sentence(trigger, in: model))
        }
    }

    private func card(_ trigger: Trigger) -> some View {
        let isActive = model.activeTriggers.contains(trigger.id)
        let sentence = TriggerText.sentence(trigger, in: model)
        return SettingsGroup {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive && trigger.isEnabled ? Theme.accent : Theme.tertiaryText)
                    .frame(width: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: sentence)
                        .font(.system(size: 13))
                        .foregroundStyle(trigger.isEnabled ? Theme.text : Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let problem = TriggerText.problem(trigger, in: model) {
                        Text(verbatim: problem).font(.system(size: 11)).foregroundStyle(Theme.warning)
                    }
                    HStack(spacing: 8) {
                        Button(Strings.editMenuItem) { editing = TriggerDraft(editing: trigger, in: model.settings) }
                            .buttonStyle(PillButtonStyle(.secondary))
                        Button(Strings.delete) { confirmingDelete = trigger }.buttonStyle(PillButtonStyle(.destructive))
                        if isActive && trigger.isEnabled { activeMark }
                    }
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(get: { trigger.isEnabled }, set: { isEnabled in
                    var changed = trigger
                    changed.isEnabled = isEnabled
                    model.saveTrigger(changed)
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(verbatim: sentence))
            }
            .padding(.vertical, 6)
        }
    }

    /// A small honey mark while the trigger's condition holds.
    private var activeMark: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6)
            Text(verbatim: Strings.activeNow)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.selection))
    }
}

/// Adds or edits a trigger: When (a condition and its value), Then (an action and its target), and the sentence they
/// make.
struct TriggerEditor: View {
    let model: InterfaceModel
    @State var draft: TriggerDraft
    let onSave: (Trigger) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: draft.isNew ? Strings.newTrigger : Strings.editTrigger).font(.system(size: 20, weight: .semibold))
            SettingsGroup(title: Strings.when) {
                Picker("", selection: $draft.condition) {
                    ForEach(TriggerCondition.Kind.allCases, id: \.self) { kind in
                        Text(verbatim: Strings.conditionName(kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .padding(.vertical, 4)
                conditionDetail
            }
            SettingsGroup(title: Strings.then) {
                Picker("", selection: $draft.action) {
                    ForEach(TriggerAction.Kind.allCases, id: \.self) { kind in
                        Text(verbatim: Strings.actionName(kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .padding(.vertical, 4)
                actionDetail
            }
            Group {
                if let trigger = draft.trigger {
                    Text(verbatim: TriggerText.sentence(trigger, in: model))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 16, alignment: .topLeading)
            HStack(spacing: 10) {
                Spacer()
                Button(Strings.cancel, action: onCancel).buttonStyle(PillButtonStyle(.secondary)).keyboardShortcut(.cancelAction)
                Button(draft.isNew ? Strings.addTrigger : Strings.save) {
                    if let trigger = draft.trigger { onSave(trigger) }
                }
                .buttonStyle(PillButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trigger == nil)
            }
        }
        .padding(24)
        .frame(width: 580)
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var conditionDetail: some View {
        switch draft.condition {
        case .appOpen, .appInFront:
            SettingRow(title: Strings.app) { AppPicker(bundleID: $draft.app) }
        case .batteryAtOrBelow:
            SettingRow(title: Strings.level, note: Strings.batteryLevelNote) {
                Stepper(value: $draft.percent, in: TriggerDraft.percentRange, step: 5) {
                    Text(verbatim: Strings.percent(draft.percent)).monospacedDigit()
                }
            }
        case .timeOfDay:
            SettingRow(title: Strings.from) {
                DatePicker("", selection: time(\.from), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field)
            }
            SettingRow(title: Strings.to, note: draft.from == draft.to
                ? Strings.sameTimes
                : Strings.timeRangeNote(from: Strings.time(ofMinutes: 22 * 60), to: Strings.time(ofMinutes: 7 * 60))) {
                DatePicker("", selection: time(\.to), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field)
            }
        case .cameraOrMicrophone:
            note(Strings.cameraOrMicrophoneNote)
        case .onBattery, .externalDisplay:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionDetail: some View {
        switch draft.action {
        case .switchProfile:
            if model.settings.profiles.isEmpty {
                note(Strings.needsAProfile)
            } else {
                SettingRow(title: Strings.profile, note: Strings.profileEndsNote) {
                    Picker("", selection: $draft.profile) {
                        if draft.profile == nil { Text(verbatim: Strings.chooseOne).tag(UUID?.none) }
                        ForEach(model.settings.profiles) { profile in
                            Text(verbatim: Strings.name(of: profile)).tag(Optional(profile.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
        case .showDrawer:
            if model.settings.layout.drawers.isEmpty {
                note(Strings.needsADrawer)
            } else {
                SettingRow(title: Strings.drawer) {
                    Picker("", selection: $draft.drawer) {
                        if draft.drawer == nil { Text(verbatim: Strings.chooseOne).tag(UUID?.none) }
                        ForEach(model.settings.layout.drawers) { drawer in
                            Text(verbatim: drawer.name).tag(Optional(drawer.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
        case .showIcon:
            let choices = iconChoices
            if choices.isEmpty {
                note(Strings.needsAnIcon)
            } else {
                SettingRow(title: Strings.icon) {
                    Picker("", selection: $draft.icon) {
                        if draft.icon == nil { Text(verbatim: Strings.chooseOne).tag(IconID?.none) }
                        ForEach(choices) { choice in
                            Text(verbatim: choice.name).tag(Optional(choice.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
        case .focus:
            note(Strings.focusShortcutNote)
        }
    }

    private struct IconChoice: Identifiable {
        var id: IconID
        var name: String
    }

    /// The icons Tiroir can show, as they are named in drawers; the chosen one stays offered while its app is closed.
    private var iconChoices: [IconChoice] {
        var choices = model.icons.filter(\.isMovable).map { row in
            IconChoice(id: row.id, name: row.subtitle.map { Strings.nameWithLabel(row.name, $0) } ?? row.name)
        }
        if let icon = draft.icon, !choices.contains(where: { $0.id == icon }) {
            choices.append(IconChoice(id: icon, name: TriggerText.iconName(icon, in: model)))
        }
        return choices
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }

    private func time(_ keyPath: WritableKeyPath<TriggerDraft, Int>) -> Binding<Date> {
        Binding(get: {
            let minutes = draft[keyPath: keyPath]
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            draft[keyPath: keyPath] = TriggerSchedule.minutesSinceMidnight(of: date, calendar: .current)
        })
    }
}

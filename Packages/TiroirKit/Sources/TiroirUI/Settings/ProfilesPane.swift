import AppKit
import SwiftUI
import TiroirCore

/// Settings, Profiles: every saved setup of the menu bar on a card, the active one marked, each with its shortcut, and
/// the current setup saved as a new profile in one click.
struct ProfilesPane: View {
    @Bindable var model: InterfaceModel
    @State private var naming: Naming?
    @State private var namingTitle = ""
    @State private var draftName = ""
    @State private var confirmingDelete: Profile?

    /// What the name field is for.
    private enum Naming: Equatable {
        case new
        case rename(UUID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.settings.profiles.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: Strings.profilesSubtitle).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: Strings.noProfilesYet).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(Strings.saveCurrentAsProfile) { startNaming(.new) }.buttonStyle(PillButtonStyle(.primary))
                }
            } else {
                Text(verbatim: Strings.profilesSubtitle).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.settings.profiles) { profile in
                        card(profile)
                    }
                }
                Button(Strings.saveCurrentAsProfile) { startNaming(.new) }.buttonStyle(PillButtonStyle(.secondary))
            }
        }
        .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField(Strings.name, text: $draftName)
            Button(naming == .new ? Strings.save : Strings.rename) { finishNaming() }
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(Strings.cancel, role: .cancel) { naming = nil }
        } message: {
            if naming == .new { Text(verbatim: Strings.newProfileMessage) }
        }
        .confirmationDialog(
            confirmingDelete.map { Strings.deleteProfileQuestion(Strings.name(of: $0)) } ?? "",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })
        ) {
            Button(Strings.delete, role: .destructive) {
                if let profile = confirmingDelete { model.update { $0.deleteProfile(profile.id) } }
                confirmingDelete = nil
            }
            Button(Strings.cancel, role: .cancel) { confirmingDelete = nil }
        }
    }

    private func card(_ profile: Profile) -> some View {
        let isActive = profile.id == model.settings.activeProfile
        return SettingsGroup {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 16, height: 28)
                    .contentShape(Rectangle())
                    .draggable(profile.id.uuidString) {
                        Text(verbatim: Strings.name(of: profile)).font(.system(size: 12, weight: .medium)).padding(6)
                    }
                    .help(Strings.dragToReorder)
                marks(profile)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: Strings.name(of: profile)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if isActive { activeBadge }
                    }
                    Text(verbatim: Strings.drawerCount(profile.layout.drawers.count))
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                }
                Spacer(minLength: 8)
                if !isActive {
                    Button(Strings.switchButton) { model.switchProfile(to: profile.id) }.buttonStyle(PillButtonStyle(.secondary))
                }
                Menu {
                    Button(Strings.renameMenuItem) { startNaming(.rename(profile.id), name: profile.name) }
                    Button(Strings.duplicate) {
                        model.update { $0.duplicateProfile(profile.id, named: Strings.copyName(Strings.name(of: profile))) }
                    }
                    Divider()
                    Button(Strings.delete, role: .destructive) { confirmingDelete = profile }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 15))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text(verbatim: Strings.moreActions))
            }
            .padding(.vertical, 6)
            Divider().opacity(0.5)
            SettingRow(title: Strings.shortcut) {
                ShortcutRecorder(shortcut: Binding(get: { profile.shortcut }, set: { shortcut in
                    model.update { $0.setShortcut(shortcut, ofProfile: profile.id) }
                }), problem: model.refusedShortcuts.contains(profile.id.uuidString) ? Strings.shortcutTaken : nil)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init(uuidString:)), dragged != profile.id,
                  let target = model.settings.profiles.firstIndex(where: { $0.id == profile.id }) else { return false }
            model.update { $0.moveProfile(dragged, to: target) }
            return true
        }
        .accessibilityAction(named: Text(verbatim: Strings.moveUp)) { move(profile, by: -1) }
        .accessibilityAction(named: Text(verbatim: Strings.moveDown)) { move(profile, by: 1) }
    }

    /// The profile's drawers as the menu bar shows them, the first four.
    private func marks(_ profile: Profile) -> some View {
        HStack(spacing: 7) {
            if profile.layout.drawers.isEmpty {
                Image(systemName: "menubar.rectangle").font(.system(size: 13))
            } else {
                ForEach(profile.layout.drawers.prefix(4)) { MarkView($0.mark, size: 14) }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8)
        .frame(minWidth: 44, minHeight: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityHidden(true)
    }

    private var activeBadge: some View {
        Text(verbatim: Strings.activeProfileBadge).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.selection))
    }

    private func startNaming(_ purpose: Naming, name: String = "") {
        namingTitle = purpose == .new ? Strings.newProfileTitle : Strings.renameProfileTitle
        draftName = purpose == .new ? model.settings.nextProfileName(Strings.numberedProfileName) : name
        naming = purpose
    }

    private func finishNaming() {
        switch naming {
        case .new?: model.saveCurrentAsProfile(named: draftName)
        case .rename(let id)?: model.update { $0.renameProfile(id, to: draftName) }
        case nil: break
        }
        naming = nil
    }

    private func move(_ profile: Profile, by offset: Int) {
        guard let index = model.settings.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        model.update { $0.moveProfile(profile.id, to: index + offset) }
    }
}

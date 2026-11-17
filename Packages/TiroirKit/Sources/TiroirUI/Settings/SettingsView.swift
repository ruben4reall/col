import AppKit
import SwiftUI
import TiroirCore
import TiroirSystem

/// Settings (spec 6.3): one dark window with a sidebar, in the family of Pli and Islet.
public struct SettingsView: View {
    @Bindable var model: InterfaceModel

    public init(model: InterfaceModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { model.settingsPane }, set: { if let pane = $0 { model.settingsPane = pane } })) { pane in
                Label { Text(verbatim: title(pane)) } icon: { Image(systemName: symbol(pane)) }
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(verbatim: title(model.settingsPane)).font(.system(size: 22, weight: .semibold))
                    EngineBanner(model: model)
                    pane
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.window)
        }
        .frame(minWidth: 820, minHeight: 600)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var pane: some View {
        switch model.settingsPane {
        case .layout: LayoutPane(model: model)
        case .drawers: DrawersPane(model: model)
        case .profiles: ProfilesPane(model: model)
        case .triggers: TriggersPane(model: model)
        case .appearance: AppearancePane(model: model)
        case .behavior: BehaviorPane(model: model)
        case .shortcuts: ShortcutsPane(model: model)
        case .general: GeneralPane(model: model)
        case .about: AboutPane(model: model)
        }
    }

    func title(_ pane: SettingsPane) -> String {
        switch pane {
        case .layout: Strings.layout
        case .drawers: Strings.drawers
        case .profiles: Strings.profiles
        case .triggers: Strings.triggers
        case .appearance: Strings.appearance
        case .behavior: Strings.behavior
        case .shortcuts: Strings.shortcuts
        case .general: Strings.general
        case .about: Strings.about
        }
    }

    func symbol(_ pane: SettingsPane) -> String {
        switch pane {
        case .layout: "rectangle.3.group"
        case .drawers: "archivebox"
        case .profiles: "square.stack.3d.up"
        case .triggers: "bolt"
        case .appearance: "paintbrush"
        case .behavior: "cursorarrow.click.2"
        case .shortcuts: "command"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

/// Says plainly when the engine cannot work, and what to do.
struct EngineBanner: View {
    let model: InterfaceModel

    var body: some View {
        switch model.engineStatus {
        case .ready:
            EmptyView()
        case .needsAccessibility:
            banner(Strings.needsAccessibilityBanner, button: Strings.openSystemSettings) {
                model.actions.requestAccessibility()
                model.actions.openAccessibilitySettings()
            }
        case .needsApplicationsFolder:
            banner(Strings.needsApplicationsBanner, button: Strings.moveToApplications) { model.actions.moveToApplications() }
        case .unavailable(let detail):
            banner(Strings.unavailableBanner(detail), button: Strings.tryAgain) { model.actions.retry() }
        }
    }

    private func banner(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(verbatim: text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(button, action: action).buttonStyle(PillButtonStyle(.primary))
        }
        .padding(14)
        .card(radius: Theme.radius)
    }
}

/// A labelled row of a settings group.
struct SettingRow<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.system(size: 13))
                if let note {
                    Text(verbatim: note).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 6)
    }
}

/// A group of settings rows on a card.
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionTitle(title) }
            VStack(alignment: .leading, spacing: 4) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }
}

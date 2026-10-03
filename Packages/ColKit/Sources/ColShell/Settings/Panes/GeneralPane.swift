import AppKit
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var fullScreen = Preferences.hidesInFullScreen
    @State private var display = Preferences.displayChoice
    @State private var keepsClipboard = Preferences.keepsClipboardHistory
    @State private var hidden = Preferences.hiddenFromScreenCapture
    @State private var automatic = Updates.checker?.automaticallyChecksForUpdates ?? false
    @State private var language = AppLanguage.chosen ?? ""

    var body: some View {
        PaneScaffold(pane: .general) {
            Section {
                IconToggle(symbol: "power", tint: .green, title: "Open Col at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) {
                        do {
                            if launchesAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchesAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker(selection: $display) {
                    Text("The screen with the notch", bundle: .module).tag("notch")
                    Text("The screen you are working on", bundle: .module).tag("main")
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "display", tint: .blue)
                        Text("Show the island on", bundle: .module)
                    }
                }
                .onChange(of: display) { Preferences.displayChoice = display }
                IconToggle(symbol: "arrow.up.left.and.arrow.down.right", tint: .gray, title: "Step aside in full screen",
                           detail: "Volume, alerts and requests still show.", isOn: $fullScreen)
                    .onChange(of: fullScreen) { Preferences.hidesInFullScreen = fullScreen }
            } header: {
                Text("Behaviour", bundle: .module)
            }
            Section {
                Picker(selection: $language) {
                    Text("Same as the Mac (\(AppLanguage.name(for: AppLanguage.system)))", bundle: .module).tag("")
                    Divider()
                    ForEach(AppLanguage.available, id: \.self) { identifier in
                        Text(verbatim: AppLanguage.name(for: identifier)).tag(identifier)
                    }
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "globe", tint: .blue)
                        Text("Language", bundle: .module)
                    }
                }
                .onChange(of: language) { AppLanguage.choose(language.isEmpty ? nil : language) }
                Link(destination: URL(string: "https://github.com/ruben4reall/col/blob/main/CONTRIBUTING.md#translations")!) {
                    Text("Improve a Translation…", bundle: .module)
                }
                if languagePending {
                    IconRow(symbol: "arrow.clockwise", tint: Theme.accent, title: Text("Col speaks the new language after a restart.", bundle: .module)) {
                        Button { AppLanguage.relaunch() } label: { Text("Restart Col", bundle: .module) }
                    }
                }
            } footer: {
                Text("Col follows the language of your Mac. If a word sounds wrong, you can fix it.", bundle: .module)
            }
            Section {
                IconToggle(symbol: "doc.on.clipboard.fill", tint: .orange, title: "Keep recent copies",
                           detail: "Kept in memory only, except the copies you pin, which are saved in Col’s settings. Copies from password managers are skipped.", isOn: $keepsClipboard)
                    .onChange(of: keepsClipboard) { Preferences.keepsClipboardHistory = keepsClipboard }
                IconToggle(symbol: "eye.slash.fill", tint: .indigo, title: "Hide the island from screenshots and recordings",
                           detail: "Useful when you share your screen.", isOn: $hidden)
                    .onChange(of: hidden) { Preferences.hiddenFromScreenCapture = hidden }
            } header: {
                Text("Privacy", bundle: .module)
            }
            if let checker = Updates.checker {
                Section {
                    if let pending = checker.pendingUpdateVersion {
                        IconRow(symbol: "arrow.down.circle.fill", tint: Theme.accent, title: Text("Col \(pending) is available", bundle: .module)) {
                            Button { checker.checkForUpdates() } label: { Text("Install…", bundle: .module) }
                        }
                    }
                    IconToggle(symbol: "arrow.triangle.2.circlepath", tint: .green, title: "Check for updates automatically", isOn: $automatic)
                        .onChange(of: automatic) { checker.automaticallyChecksForUpdates = automatic }
                    LabeledContent {
                        Button { checker.checkForUpdates() } label: { Text("Check Now", bundle: .module) }
                            .disabled(!checker.canCheckForUpdates)
                    } label: {
                        Text("Version \(AboutPane.version)", bundle: .module)
                    }
                } header: {
                    Text("Updates", bundle: .module)
                } footer: {
                    Text("Updates are signed and come from the Col website.", bundle: .module)
                }
            }
            Section {
                Button { WelcomeWindow.shared.show() } label: { Text("Show the Welcome Again…", bundle: .module) }
            }
        }
    }

    /// A language was picked that differs from the one on screen.
    private var languagePending: Bool {
        (language.isEmpty ? AppLanguage.system : language) != AppLanguage.current
    }
}

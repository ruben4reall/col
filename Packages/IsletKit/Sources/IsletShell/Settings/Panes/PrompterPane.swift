import AppKit
import IsletCore
import IsletPrompter
import Speech
import SwiftUI

/// The prompter: how the script moves, where it appears, how it reads, and every way to drive it.
struct PrompterPane: View {
    @State private var center = PrompterCenter.shared
    @AppStorage(PrompterPreferences.Key.mode) private var mode = ScrollMode.pace.rawValue
    @AppStorage(PrompterPreferences.Key.wordsPerMinute) private var pace = Pace.conversational
    @AppStorage(PrompterPreferences.Key.voiceLanguage) private var language = "auto"
    @AppStorage(PrompterPreferences.Key.placement) private var placement = PrompterPlacement.notch.rawValue
    @AppStorage(PrompterPreferences.Key.notchWidth) private var notchWidth = 400.0
    @AppStorage(PrompterPreferences.Key.notchLines) private var notchLines = 4.0
    @AppStorage(PrompterPreferences.Key.floatingWidth) private var floatingWidth = 520.0
    @AppStorage(PrompterPreferences.Key.floatingHeight) private var floatingHeight = 200.0
    @AppStorage(PrompterPreferences.Key.fullScreenDisplay) private var fullScreenDisplay = ""
    @AppStorage(PrompterPreferences.Key.fullScreenFontSize) private var fullScreenFontSize = 64.0
    @AppStorage(PrompterPreferences.Key.font) private var font = PrompterFont.system.rawValue
    @AppStorage(PrompterPreferences.Key.fontSize) private var fontSize = 21.0
    @AppStorage(PrompterPreferences.Key.lineSpacing) private var lineSpacing = 1.4
    @AppStorage(PrompterPreferences.Key.alignment) private var alignment = "center"
    @AppStorage(PrompterPreferences.Key.theme) private var theme = PrompterTheme.night.rawValue
    @AppStorage(PrompterPreferences.Key.dimsReadWords) private var dimsReadWords = true
    @AppStorage(PrompterPreferences.Key.mirror) private var mirror = MirrorMode.none.rawValue
    @AppStorage(PrompterPreferences.Key.countdown) private var countdown = true
    @AppStorage(PrompterPreferences.Key.showsTimer) private var showsTimer = true
    @AppStorage(PrompterPreferences.Key.hiddenFromCapture) private var hiddenFromCapture = true
    @AppStorage(PrompterPreferences.Key.stageLight) private var light = StageLight.accent.rawValue
    @AppStorage(PrompterPreferences.Key.hotKeys) private var hotKeys = true
    @AppStorage(PrompterPreferences.Key.clickerKeys) private var clickerKeys = true
    @AppStorage(PrompterPreferences.Key.remoteEnabled) private var remoteEnabled = false
    @State private var locales: [Locale] = []

    var body: some View {
        PaneScaffold(pane: .prompter) {
            Section {
                IconRow(symbol: "doc.text.fill", tint: Theme.accent, title: Text("Scripts", bundle: .module),
                        detail: Text("\(center.store.documents.count) in your library. Drop a text, a Word document, a PDF or a presentation on it.", bundle: .module)) {
                    HStack(spacing: 8) {
                        Button { center.prompt(text: ScriptStore.welcomeScript, title: String(localized: "Prompter", bundle: .module)) } label: {
                            Text("Try It", bundle: .module)
                        }
                        Button { center.showLibrary() } label: { Text("Open Scripts…", bundle: .module) }
                    }
                }
            }
            Section {
                ForEach(ScrollMode.allCases) { option in
                    Button { mode = option.rawValue } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: option.symbol, tint: mode == option.rawValue ? Theme.accent : .gray)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: option.title).foregroundStyle(.primary)
                                Text(verbatim: option.subtitle).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if mode == option.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.bold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                LabeledContent {
                    HStack {
                        Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                        Slider(value: $pace, in: PrompterPreferences.minimumPace...PrompterPreferences.maximumPace, step: 5)
                        Image(systemName: "hare.fill").foregroundStyle(.secondary)
                        Text("\(Int(pace)) wpm", bundle: .module).monospacedDigit().foregroundStyle(.secondary).fixedSize().frame(minWidth: 70, alignment: .trailing)
                    }
                } label: {
                    Text("Pace", bundle: .module)
                }
                Picker(selection: $language) {
                    Text("Same as the script", bundle: .module).tag("auto")
                    Divider()
                    ForEach(locales, id: \.identifier) { locale in
                        Text(verbatim: Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).tag(locale.identifier)
                    }
                } label: {
                    Text("Voice language", bundle: .module)
                }
            } header: {
                Text("How the script moves", bundle: .module)
            } footer: {
                Text("Your voice is heard on your Mac and never recorded. The recognizer is given the words of your script, so names and jargon are heard right.", bundle: .module)
            }
            Section {
                Picker(selection: $placement) {
                    ForEach(PrompterPlacement.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
                } label: {
                    Text("Show the prompter", bundle: .module)
                }
                .pickerStyle(.segmented)
                switch PrompterPlacement(rawValue: placement) ?? .notch {
                case .notch:
                    slider(Text("Width", bundle: .module), value: $notchWidth, in: 380...760, step: 10, unit: "pt")
                    Stepper(value: $notchLines, in: 2...8) {
                        LabeledContent { Text(verbatim: "\(Int(notchLines))") } label: { Text("Lines", bundle: .module) }
                    }
                case .floating:
                    slider(Text("Width", bundle: .module), value: $floatingWidth, in: 380...1200, step: 10, unit: "pt")
                    slider(Text("Height", bundle: .module), value: $floatingHeight, in: 140...700, step: 10, unit: "pt")
                case .fullScreen:
                    Picker(selection: $fullScreenDisplay) {
                        Text("Automatic", bundle: .module).tag("")
                        ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { Text(verbatim: $0).tag($0) }
                    } label: { Text("Display", bundle: .module) }
                    slider(Text("Text size", bundle: .module), value: $fullScreenFontSize, in: 36...140, step: 2, unit: "pt")
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        ForEach(StageLight.allCases) { option in
                            Button { light = option.rawValue } label: {
                                LightSwatch(light: option, selected: light == option.rawValue)
                            }
                            .buttonStyle(.plain)
                            .help(Text(verbatim: option.title))
                        }
                    }
                } label: {
                    Text("Stage light", bundle: .module)
                }
            } header: {
                Text("Place", bundle: .module)
            } footer: {
                Text("In the notch, the prompter grows from the camera and the island steps aside until the take ends. The stage light glows inside it and brightens with your voice.", bundle: .module)
            }
            Section {
                Picker(selection: $font) {
                    ForEach(PrompterFont.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
                } label: { Text("Font", bundle: .module) }
                slider(Text("Size", bundle: .module), value: $fontSize, in: 14...48, step: 1, unit: "pt")
                slider(Text("Line spacing", bundle: .module), value: $lineSpacing, in: 1.0...1.8, step: 0.05, unit: "×")
                Picker(selection: $alignment) {
                    Text("Centered", bundle: .module).tag("center")
                    Text("Left", bundle: .module).tag("left")
                } label: { Text("Alignment", bundle: .module) }
                    .pickerStyle(.segmented)
                Picker(selection: $theme) {
                    ForEach(PrompterTheme.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
                } label: { Text("Colors", bundle: .module) }
                    .pickerStyle(.segmented)
                Toggle(isOn: $dimsReadWords) { Text("Dim the words already read", bundle: .module) }
                Picker(selection: $mirror) {
                    ForEach(MirrorMode.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
                } label: { Text("Mirror", bundle: .module) }
            } header: {
                Text("Text", bundle: .module)
            }
            Section {
                Toggle(isOn: $countdown) { Text("Count down from 3 before rolling", bundle: .module) }
                Toggle(isOn: $showsTimer) { Text("Show the timer", bundle: .module) }
                Toggle(isOn: $hiddenFromCapture) {
                    Text("Hide from screen sharing and recordings", bundle: .module)
                    Text("The prompter stays on your screen and out of screenshots, recordings and calls. Turn this off to show it in a tutorial.", bundle: .module)
                }
            } header: {
                Text("Take", bundle: .module)
            }
            Section {
                Toggle(isOn: $hotKeys) { Text("Keyboard shortcuts in every app", bundle: .module) }
                if hotKeys {
                    if !center.takenShortcuts.isEmpty {
                        Label {
                            Text("Another app already uses \(center.takenShortcuts.formatted(.list(type: .and))). Quit it or change its shortcut, then turn this off and on.", bundle: .module)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        }
                        .font(.callout)
                    }
                    shortcut(["⌃", "⌥", "⌘", "P"], Text("Prompt the selected script, play or pause", bundle: .module))
                    shortcut(["⌃", "⌥", "⌘", "↑", "↓"], Text("Faster, slower", bundle: .module))
                    shortcut(["⌃", "⌥", "⌘", "←", "→"], Text("Back or forward a line", bundle: .module))
                    shortcut(["⌃", "⌥", "⌘", "R"], Text("Restart", bundle: .module))
                    shortcut(["⌃", "⌥", "⌘", "H"], Text("Show or hide the prompter", bundle: .module))
                }
                Toggle(isOn: $clickerKeys) {
                    Text("Presentation remotes and foot pedals", bundle: .module)
                    Text("While the prompter is open, Page Down moves on a line, or starts a paused take, and Page Up goes back. The rest of the time these keys work as usual.", bundle: .module)
                }
            } header: {
                Text("Controls", bundle: .module)
            }
            Section {
                Toggle(isOn: $remoteEnabled) {
                    Text("Phone remote", bundle: .module)
                    Text("Your phone must be on the same network. Only a phone that scanned this code can drive the prompter.", bundle: .module)
                }
                if remoteEnabled {
                    RemoteCard(center: center)
                }
            } header: {
                Text("Remote", bundle: .module)
            }
        }
        .onAppear {
            locales = SFSpeechRecognizer.supportedLocales().sorted {
                (Locale.current.localizedString(forIdentifier: $0.identifier) ?? "") < (Locale.current.localizedString(forIdentifier: $1.identifier) ?? "")
            }
        }
    }

    private func slider(_ title: Text, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        LabeledContent {
            HStack {
                Slider(value: value, in: range, step: step)
                Text(verbatim: step < 1 ? String(format: "%.2f%@", value.wrappedValue, unit) : "\(Int(value.wrappedValue)) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
        } label: {
            title
        }
    }

    private func shortcut(_ keys: [String], _ action: Text) -> some View {
        LabeledContent {
            KeyCaps(keys: keys)
        } label: {
            action
        }
    }
}

/// The remote's code to scan, its address and how many phones listen.
private struct RemoteCard: View {
    let center: PrompterCenter

    var body: some View {
        let _ = center.remoteRevision
        HStack(alignment: .center, spacing: 18) {
            if let address = center.remote.address, let image = QRCode.image(for: address.absoluteString, size: 150) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan with your phone’s camera", bundle: .module).font(.system(size: 13, weight: .semibold))
                    Text(verbatim: address.absoluteString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(center.remote.connectedCount == 0
                         ? String(localized: "No phone connected", bundle: .module)
                         : String(localized: "\(center.remote.connectedCount) connected", bundle: .module))
                        .font(.callout)
                        .foregroundStyle(center.remote.connectedCount == 0 ? Color.secondary : Theme.accent)
                    Button {
                        PrompterPreferences.renewRemoteToken()
                        center.remote.stop()
                        center.remote.start()
                    } label: { Text("New Pairing Code", bundle: .module) }
                }
            } else {
                ProgressView().controlSize(.small)
                Text("Starting the remote…", bundle: .module).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

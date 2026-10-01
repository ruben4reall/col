import SwiftUI

struct ShortcutsPane: View {
    @State private var hotKey = Preferences.hotKeyEnabled

    var body: some View {
        PaneScaffold(pane: .shortcuts) {
            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "keyboard.fill", tint: .gray)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Open or close the island", bundle: .module)
                        Text("Works in every app.", bundle: .module).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    KeyCaps(keys: ["⌃", "⌥", "⌘", "I"]).opacity(hotKey ? 1 : 0.4)
                    Toggle(String(), isOn: $hotKey).labelsHidden().toggleStyle(.switch)
                        .onChange(of: hotKey) { Preferences.hotKeyEnabled = hotKey }
                }
            } header: {
                Text("Keyboard", bundle: .module)
            }
            Section {
                gesture("cursorarrow.rays", "Rest the pointer on the notch", "It swells, then opens. The delay is in Appearance.")
                gesture("cursorarrow.click", "Click the notch", "Opens it at once.")
                gesture("arrow.down", "Swipe down with two fingers on the notch", "Opens it at once.")
                gesture("arrow.up", "Swipe up with two fingers", "Closes it.")
                gesture("arrow.left.and.right", "Swipe sideways on the open island", "Turns the pages.")
                gesture("forward.end.alt.fill", "Swipe sideways on the closed island", "Next or previous track, while music plays.")
                gesture("doc.on.doc.fill", "Drag files onto the notch", "Puts them on the shelf, ready for AirDrop.")
                gesture("contextualmenu.and.cursorarrow", "Right-click the island", "Settings, updates and Quit.")
            } header: {
                Text("Trackpad and pointer", bundle: .module)
            } footer: {
                Text("Islet only watches the pointer over the notch, never anywhere else.", bundle: .module)
            }
        }
    }

    private func gesture(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        IconRow(symbol: symbol, tint: Color(red: 0.42, green: 0.45, blue: 0.5), title: Text(title, bundle: .module), detail: Text(detail, bundle: .module)) {
            EmptyView()
        }
    }
}

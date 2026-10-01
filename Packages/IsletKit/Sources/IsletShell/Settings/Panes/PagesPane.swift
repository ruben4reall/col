import IsletCore
import SwiftUI

struct PagesPane: View {
    @State private var enabled = Preferences.enabledPages
    @State private var replay = 0

    var body: some View {
        PaneScaffold(pane: .pages) {
            Section {
                IslandStage(size: Preferences.islandSize, glass: IslandView.glassAvailable ? Preferences.islandGlass : .off, replay: replay)
                    .frame(height: IslandStage.height(for: Preferences.islandSize))
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("The tabs at the top left of the open island follow the order below. Swipe sideways on the island to turn the pages.", bundle: .module)
            }
            Section {
                PageRow(page: .home, isOn: true, fixed: true, position: nil, count: 0, toggle: { _ in }, move: { _ in })
                ForEach(IslandPage.optional) { page in
                    PageRow(page: page, isOn: enabled.contains(page.key), fixed: false, position: enabled.firstIndex(of: page.key), count: enabled.count) { on in
                        if on { enabled.append(page.key) } else { enabled.removeAll { $0 == page.key } }
                        save()
                    } move: { offset in
                        guard let index = enabled.firstIndex(of: page.key) else { return }
                        let target = min(max(index + offset, 0), enabled.count - 1)
                        enabled.move(fromOffsets: IndexSet(integer: index), toOffset: target > index ? target + 1 : target)
                        save()
                    }
                }
                PageRow(page: .live, isOn: true, fixed: true, position: nil, count: 0, toggle: { _ in }, move: { _ in })
            } header: {
                Text("Pages", bundle: .module)
            } footer: {
                Text("Home is always first. Live sits on the right of the camera while something runs. Turned-off pages leave the island entirely, tab included.", bundle: .module)
            }
        }
    }

    private func save() {
        Preferences.enabledPages = enabled
        replay += 1
    }
}

private struct PageRow: View {
    let page: IslandPage
    let isOn: Bool
    let fixed: Bool
    let position: Int?
    let count: Int
    let toggle: (Bool) -> Void
    let move: (Int) -> Void
    @State private var hovering = false
    @State private var on = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                Text(page.summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !fixed, isOn, let position, hovering {
                HStack(spacing: 2) {
                    Button { move(-1) } label: { Image(systemName: "chevron.up") }
                        .disabled(position == 0)
                        .help(Text("Move up", bundle: .module))
                    Button { move(1) } label: { Image(systemName: "chevron.down") }
                        .disabled(position == count - 1)
                        .help(Text("Move down", bundle: .module))
                }
                .buttonStyle(.borderless)
                .transition(.opacity)
            }
            if fixed {
                Text("Always", bundle: .module).foregroundStyle(.tertiary)
            } else {
                Toggle("", isOn: $on).labelsHidden().toggleStyle(.switch)
            }
        }
        .onAppear { on = isOn }
        .onChange(of: on) { if on != isOn { toggle(on) } }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension IslandPage {
    var summary: LocalizedStringResource {
        switch self {
        case .home: LocalizedStringResource("Music, clock and agenda", bundle: .settings)
        case .shelf: LocalizedStringResource("Files dropped on the notch, AirDrop", bundle: .settings)
        case .clipboard: LocalizedStringResource("Your recent copies", bundle: .settings)
        case .tools: LocalizedStringResource("Timer, colour picker, mirror", bundle: .settings)
        case .system: LocalizedStringResource("Processor, memory, disk, network", bundle: .settings)
        case .live, .greeting, .device: LocalizedStringResource("AI apps and activities from scripts", bundle: .settings)
        }
    }
}

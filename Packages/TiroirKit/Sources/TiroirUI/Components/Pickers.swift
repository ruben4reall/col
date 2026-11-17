import AppKit
import SwiftUI
import TiroirCore
import TiroirSystem

/// Records a shortcut: click, press the keys, done. Esc cancels; a key without ⌘, ⌥ or ⌃ is refused.
public struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var problem: String?
    /// Starts listening for keys as soon as it shows (a shortcut just asked for).
    var startsRecording = false
    @State private var isRecording = false
    @State private var hint: String?
    @State private var monitor: Any?

    public init(shortcut: Binding<Shortcut?>, problem: String? = nil, startsRecording: Bool = false) {
        _shortcut = shortcut
        self.problem = problem
        self.startsRecording = startsRecording
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(verbatim: isRecording ? Strings.pressShortcut : (shortcut?.display ?? Strings.recordShortcut))
                    .font(.system(size: 13, weight: shortcut == nil || isRecording ? .regular : .semibold, design: .rounded))
                    .frame(minWidth: 132)
            }
            .buttonStyle(PillButtonStyle(isRecording ? .primary : .secondary))
            if shortcut != nil, !isRecording {
                Button(Strings.clear) { shortcut = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .font(.system(size: 12))
            }
            if let message = hint ?? problem {
                Text(verbatim: message).font(.system(size: 11)).foregroundStyle(Theme.warning)
            }
        }
        .onAppear { if startsRecording, shortcut == nil { start() } }
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch ShortcutRecording.record(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                            characters: event.charactersIgnoringModifiers) {
            case .shortcut(let recorded):
                shortcut = recorded
                stop()
            case .cancel:
                stop()
            case .needsModifier:
                hint = Strings.needsModifier
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

/// Chooses a drawer's mark: an icon from the library (the default, drawn like macOS's own menu bar icons), an emoji,
/// or up to three letters.
public struct MarkPicker: View {
    @Binding var mark: DrawerMark
    @State private var tab: Tab
    @State private var text: String
    @State private var custom = ""
    @State private var query = ""

    enum Tab: Hashable { case icon, emoji, text }

    public init(mark: Binding<DrawerMark>) {
        _mark = mark
        switch mark.wrappedValue {
        case .symbol: _tab = State(initialValue: .icon); _text = State(initialValue: "")
        case .emoji: _tab = State(initialValue: .emoji); _text = State(initialValue: "")
        case .text(let value): _tab = State(initialValue: .text); _text = State(initialValue: value)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(Strings.mark, selection: $tab) {
                Text(verbatim: Strings.icon).tag(Tab.icon)
                Text(verbatim: Strings.emoji).tag(Tab.emoji)
                Text(verbatim: Strings.text).tag(Tab.text)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            switch tab {
            case .icon: iconLibrary
            case .emoji: emojiGrid
            case .text:
                TextField(Strings.upToThreeLetters, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onChange(of: text) { _, value in
                        let trimmed = String(value.prefix(DrawerMark.maximumTextLength))
                        if trimmed != value { text = trimmed }
                        let candidate = DrawerMark.text(trimmed)
                        if candidate.isValid { mark = candidate }
                    }
            }
        }
        .frame(minWidth: 300, maxWidth: 400, alignment: .leading)
    }

    private var iconLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(Strings.searchIcons, text: $query).textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            let sections = SymbolLibrary.search(query)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                    ForEach(sections) { section in
                        Text(verbatim: Strings.symbolSection(section.title))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.tertiaryText)
                            .textCase(.uppercase)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 32, maximum: 32), spacing: 4)], alignment: .leading, spacing: 4) {
                            ForEach(section.symbols, id: \.self) { name in
                                choice(isSelected: mark == .symbol(name), label: name.replacingOccurrences(of: ".", with: " ")) {
                                    mark = .symbol(name)
                                } content: {
                                    Image(systemName: name).font(.system(size: 14, weight: .medium))
                                }
                                .help(name)
                            }
                        }
                    }
                    if sections.isEmpty {
                        Text(verbatim: Strings.noSearchResult(query)).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 230)
        }
    }

    private var emojiGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(MarkLibrary.emoji, id: \.self) { emoji in
                    choice(isSelected: mark == .emoji(emoji), label: emoji) {
                        mark = .emoji(emoji)
                    } content: {
                        Text(verbatim: emoji).font(.system(size: 18))
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .accessibilityLabel(Text(verbatim: Strings.emoji))
                    .onChange(of: custom) { _, value in
                        guard let last = value.last else { return }
                        let candidate = DrawerMark.emoji(String(last))
                        if candidate.isValid { mark = candidate }
                        custom = candidate.isValid ? String(last) : ""
                    }
                Button(Strings.moreEmoji) { NSApp.orderFrontCharacterPalette(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }

    /// One choice of the grid: a real button, so the keyboard and VoiceOver reach it too.
    private func choice<Content: View>(isSelected: Bool, label: String, action: @escaping () -> Void,
                                       @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isSelected ? Theme.selection : Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

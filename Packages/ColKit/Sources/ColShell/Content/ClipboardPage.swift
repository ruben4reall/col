import ColCore
import SwiftUI

/// Recent copies: click one to put it back on the clipboard. A search field above them finds a copy by its words or
/// the app it came from.
struct ClipboardPage: View {
    let clipboard: ClipboardMonitor

    var body: some View {
        let entries = clipboard.history.ordered
        if entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Text("Nothing copied yet", bundle: .module)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Your recent copies land here. They stay in memory; only the ones you pin are saved.", bundle: .module)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if Preferences.searchesClipboard {
            let matches = clipboard.history.matching(clipboard.query)
            VStack(spacing: 6) {
                ClipboardSearchBar(clipboard: clipboard, first: matches.first)
                if matches.isEmpty {
                    Text("No copy matches “\(clipboard.query)”", bundle: .module)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(matches)
                }
            }
            // The next time the page shows, it shows every copy again.
            .onDisappear { clipboard.query = "" }
        } else {
            list(entries)
        }
    }

    private func list(_ entries: [ClipboardHistory.Entry]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 5) {
                ForEach(entries) { entry in
                    ClipRow(entry: entry, clipboard: clipboard)
                }
            }
        }
    }
}

/// The search field. Like the Ask field of the AI page, the island takes the keyboard only while it is in use, and gives
/// it back on Escape, on Return (which copies the first match), or when it closes.
private struct ClipboardSearchBar: View {
    let clipboard: ClipboardMonitor
    let first: ClipboardHistory.Entry?
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var clipboard = clipboard
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Group {
                if clipboard.searching {
                    TextField(text: $clipboard.query, prompt: prompt) { EmptyView() }
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(copyFirst)
                        .onExitCommand(perform: escape)
                } else {
                    // A plain button until the field is needed: the island lends no keyboard before.
                    Button(action: beginSearching) {
                        Group {
                            if clipboard.query.isEmpty { prompt } else { Text(verbatim: clipboard.query) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            if !clipboard.query.isEmpty {
                Button { clipboard.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(PressableStyle())
                .help(Text("Clear", bundle: .module))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Theme.fill))
        .onAppear {
            if clipboard.searching { DispatchQueue.main.async { focused = true } }
        }
    }

    private var prompt: Text {
        Text("Search your copies", bundle: .module).foregroundStyle(Theme.secondaryText)
    }

    private func beginSearching() {
        IslandController.shared?.takeKeyboard()
        clipboard.searching = true
        DispatchQueue.main.async { focused = true }
    }

    private func endSearching() {
        focused = false
        clipboard.searching = false
        IslandController.shared?.releaseKeyboard()
    }

    /// Escape clears what was typed, then gives the keyboard back.
    private func escape() {
        if clipboard.query.isEmpty { endSearching() } else { clipboard.query = "" }
    }

    private func copyFirst() {
        if let first { clipboard.copy(first) }
        endSearching()
    }
}

private struct ClipRow: View {
    let entry: ClipboardHistory.Entry
    let clipboard: ClipboardMonitor
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            clipboard.copy(entry)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 10) {
                if let data = entry.image, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 34, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else if entry.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(45))
                }
                Text(preview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.isImage ? Theme.secondaryText : .white.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                } else if hovering {
                    HStack(spacing: 10) {
                        if !entry.isImage {
                            RowIcon(symbol: entry.pinned ? "pin.slash.fill" : "pin.fill") { clipboard.togglePin(entry) }
                        }
                        RowIcon(symbol: "xmark") { withAnimation(.spring(duration: 0.3)) { clipboard.remove(entry) } }
                    }
                } else if let app = entry.sourceApp {
                    Text(app)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: entry.isImage ? 32 : 28)
            .background(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).fill(Color.white.opacity(hovering ? 0.11 : (entry.pinned ? 0.08 : 0.06))))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: copied)
        .help(entry.isImage ? entry.text : String(entry.text.prefix(400)))
    }

    private var preview: String {
        entry.text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? entry.text
    }
}

private struct RowIcon: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering ? .white : Theme.secondaryText)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }
}

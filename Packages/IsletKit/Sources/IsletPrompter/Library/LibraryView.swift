import AppKit
import IsletCore
import SwiftUI
import UniformTypeIdentifiers

/// The main window: the scripts on the left, the one being written on the right with its play button, and the speed
/// card below it.
public struct LibraryView: View {
    @Bindable var store: ScriptStore
    let app: PrompterCenter
    @State private var search = ""
    @State private var isTargeted = false
    @AppStorage(PrompterPreferences.Key.mode) private var mode = ScrollMode.pace.rawValue
    @AppStorage(PrompterPreferences.Key.placement) private var placement = PrompterPlacement.notch.rawValue
    @AppStorage(PrompterPreferences.Key.wordsPerMinute) private var pace = Pace.conversational
    @AppStorage(PrompterPreferences.Key.lastSummary) private var lastSummary = ""

    public init(app: PrompterCenter) {
        self.app = app
        store = app.store
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
        }
        .searchable(text: $search, placement: .sidebar, prompt: Text("Search", bundle: .module))
        .dropDestination(for: URL.self) { urls, _ in
            // Documents only: a link dropped here is not fetched.
            let files = urls.filter(\.isFileURL)
            return !files.isEmpty && app.importDocuments(files)
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(StageTheme.accent, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Sidebar

    private var filtered: [ScriptDocument] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.documents }
        return store.documents.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var sidebar: some View {
        List(selection: $store.selection) {
            ForEach(filtered) { document in
                ScriptRow(document: document)
                    .tag(document.id)
                    .contextMenu {
                        Button(String(localized: "Prompt", bundle: .module)) { app.prompt(document) }
                        Button(String(localized: "Duplicate", bundle: .module)) { store.duplicate(document.id) }
                        Divider()
                        Button(String(localized: "Move to Trash", bundle: .module), role: .destructive) { store.delete(document.id) }
                    }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button { store.create() } label: {
                    Label(String(localized: "New Script", bundle: .module), systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n")
                .help(String(localized: "New Script (⌘N)", bundle: .module))
            }
            ToolbarItem {
                Button { ScriptImportPanel.run(app: app) } label: {
                    Label(String(localized: "Import…", bundle: .module), systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("o")
                .help(String(localized: "Import a text, a Word document, a PDF or a presentation's notes (⌘O)", bundle: .module))
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let document = store.selected {
            VStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    ScriptEditor(documentID: document.id, text: Binding(
                        get: { store.document(document.id)?.text ?? "" },
                        set: { store.update(document.id, text: $0) }
                    ), onDropFiles: { app.importDocuments($0) })
                    PlayButton(app: app)
                        .padding(18)
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(StageTheme.card))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                SpeedPanel(document: document, pace: $pace, mode: $mode, lastSummary: lastSummary)
            }
            .padding(14)
            .navigationTitle(document.title)
            .toolbar { promptToolbar }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Script", bundle: .module), systemImage: "text.alignleft")
            } description: {
                Text("Write a new script, or drop a text file, a Word document, a PDF or a presentation here.", bundle: .module)
            } actions: {
                Button(String(localized: "New Script", bundle: .module)) { store.create() }
                    .buttonStyle(.borderedProminent)
                    .tint(StageTheme.accent)
            }
        }
    }

    @ToolbarContentBuilder private var promptToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker(String(localized: "Scrolling", bundle: .module), selection: $mode) {
                    ForEach(ScrollMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                let current = ScrollMode(rawValue: mode) ?? .auto
                Label(current.title, systemImage: current.symbol)
                    .labelStyle(.titleAndIcon)
            }
            .help(String(localized: "How the script moves", bundle: .module))

            Menu {
                Picker(String(localized: "Place", bundle: .module), selection: $placement) {
                    ForEach(PrompterPlacement.allCases) { place in
                        Text(place.title).tag(place.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label((PrompterPlacement(rawValue: placement) ?? .notch).title, systemImage: placementSymbol)
                    .labelStyle(.titleAndIcon)
            }
            .help(String(localized: "Where the prompter appears", bundle: .module))

        }
    }

    private var placementSymbol: String {
        switch PrompterPlacement(rawValue: placement) ?? .notch {
        case .notch: "macbook"
        case .floating: "rectangle.on.rectangle"
        case .fullScreen: "rectangle.inset.filled"
        }
    }

}

private struct ScriptRow: View {
    let document: ScriptDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(document.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if !document.preview.isEmpty {
                Text(document.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(document.modified, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

/// Asks for documents to import into the library.
@MainActor
public enum ScriptImportPanel {
    public static func run(app: PrompterCenter) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ScriptImporter.contentTypes
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Import", bundle: .module)
        guard panel.runModal() == .OK else { return }
        app.importDocuments(panel.urls)
    }
}

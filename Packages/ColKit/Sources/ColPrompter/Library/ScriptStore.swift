import AppKit
import Foundation
import Observation
import ColCore

/// A script in the library.
public struct ScriptDocument: Identifiable, Hashable, Sendable {
    public let id: String
    public var text: String
    public var modified: Date

    /// The first line with words, without its markup, or "Untitled Script".
    public var title: String {
        for line in text.split(separator: "\n") {
            let plain = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "# \t"))
            if !plain.isEmpty { return String(plain.prefix(80)) }
        }
        return String(localized: "Untitled Script", bundle: .module)
    }

    /// The words after the title line, for the list.
    public var preview: String {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let line = lines.dropFirst().first else { return "" }
        let withoutCues = line.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        return Script(withoutCues).display.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    public var wordCount: Int { Script(text).words.count }
}

/// The library: one Markdown file per script in Application Support, saved as you type.
@MainActor
@Observable
public final class ScriptStore {
    public private(set) var documents: [ScriptDocument] = []
    public var selection: String? {
        didSet { UserDefaults.standard.set(selection, forKey: PrompterPreferences.Key.selectedScript) }
    }

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var pendingSaves: [String: Task<Void, Never>] = [:]
    /// Scripts whose last change is not on disk yet: written again at the next change or when quitting.
    @ObservationIgnored private var unsaved: Set<String> = []
    @ObservationIgnored private var warnedAboutSaving = false

    public init(folder: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = folder ?? support.appendingPathComponent("Col/Scripts", isDirectory: true)
        self.folder = folder
        Self.adoptSouffleurScripts(into: folder, from: support.appendingPathComponent("Souffleur/Scripts", isDirectory: true))
        load()
    }

    /// The prompter was an app of its own, Souffleur, before it joined Col. Its scripts are copied over once, the
    /// first time the library opens; the originals stay where they were.
    static func adoptSouffleurScripts(into folder: URL, from previous: URL) {
        let files = FileManager.default
        guard !files.fileExists(atPath: folder.path),
              let scripts = try? files.contentsOfDirectory(at: previous, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "md" }),
              !scripts.isEmpty
        else { return }
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        for script in scripts {
            try? files.copyItem(at: script, to: folder.appendingPathComponent(script.lastPathComponent))
        }
        // Souffleur's own welcome script was seeded already: do not seed Col's on top of the user's scripts.
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    static let seededKey = "prompter.seededLibrary"

    public func load() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        documents = files.filter { $0.pathExtension == "md" }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ScriptDocument(id: url.deletingPathExtension().lastPathComponent, text: text, modified: modified)
        }.sorted { $0.modified > $1.modified }
        if documents.isEmpty, !UserDefaults.standard.bool(forKey: Self.seededKey) {
            UserDefaults.standard.set(true, forKey: Self.seededKey)
            create(text: Self.welcomeScript)
        }
        let saved = UserDefaults.standard.string(forKey: PrompterPreferences.Key.selectedScript)
        selection = documents.contains { $0.id == saved } ? saved : documents.first?.id
    }

    public func document(_ id: String?) -> ScriptDocument? {
        guard let id else { return nil }
        return documents.first { $0.id == id }
    }

    public var selected: ScriptDocument? { document(selection) }

    @discardableResult
    public func create(text: String = "") -> ScriptDocument {
        let document = ScriptDocument(id: UUID().uuidString, text: text, modified: Date())
        documents.insert(document, at: 0)
        save(document)
        selection = document.id
        return document
    }

    /// Keeps the text in memory at once and writes it a moment after the last keystroke.
    public func update(_ id: String, text: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }), documents[index].text != text else { return }
        documents[index].text = text
        documents[index].modified = Date()
        let document = documents[index]
        unsaved.insert(id)
        pendingSaves[id]?.cancel()
        pendingSaves[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.pendingSaves[id] = nil
            self.save(document)
        }
    }

    public func duplicate(_ id: String) {
        guard let original = document(id) else { return }
        create(text: original.text)
    }

    public func delete(_ id: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        unsaved.remove(id)
        let url = fileURL(id)
        // To the Trash rather than gone: a script deleted by mistake can be put back.
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        documents.remove(at: index)
        if selection == id { selection = documents[safe: min(index, documents.count - 1)]?.id }
    }

    /// Writes every change not yet on disk, before prompting or quitting.
    public func flush() {
        pendingSaves.values.forEach { $0.cancel() }
        pendingSaves.removeAll()
        for id in unsaved {
            if let document = document(id) { save(document) }
        }
    }

    public func revealInFinder() {
        NSWorkspaceBridge.reveal(folder)
    }

    private func fileURL(_ id: String) -> URL { folder.appendingPathComponent(id).appendingPathExtension("md") }

    /// Writes a script, and says so once if the disk refuses: the text stays in the window and is written again at
    /// the next change.
    private func save(_ document: ScriptDocument) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try document.text.write(to: fileURL(document.id), atomically: true, encoding: .utf8)
            unsaved.remove(document.id)
        } catch {
            unsaved.insert(document.id)
            guard !warnedAboutSaving else { return }
            warnedAboutSaving = true
            let alert = NSAlert()
            alert.messageText = String(localized: "Col can't save “\(document.title)”.", bundle: .module)
            alert.informativeText = String(localized: "\(error.localizedDescription) Your text stays in the window, and Col tries again at your next change.", bundle: .module)
            alert.runModal()
        }
    }

    /// The first script, in the user's language: how the prompter works, to read aloud.
    public static var welcomeScript: String {
        String(localized: """
        # Welcome to the prompter
        Hello, and welcome to Col's prompter. [smile]
        Your script comes out of the notch, right under your camera, so you can read it and still look your audience in the eye.
        Press play and start speaking. When you stop talking, the script stops with you, and it rolls on as soon as you speak again.
        Move the speed until the words arrive just as you need them. Or choose Voice Follow, and the script follows your words, line by line. [pause]

        # Make it yours
        Write your own script in this window, or drop a document on it: a text file, a Word document, a PDF, or the speaker notes of a presentation.
        Put a cue in square brackets, like [breathe], and it shows quietly. Two stars around a word make it **stand out**.
        When you are ready, press play, look at the camera, and speak.
        """, bundle: .module)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

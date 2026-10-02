import AppKit
import ColCore
import Observation

/// A short conversation with one of the user's models, from the island. The question goes to the server the user
/// added (or the Mac's own Ollama or LM Studio), nowhere else; the answer arrives word by word.
@MainActor
@Observable
final class AskSession {
    struct Choice: Equatable, Hashable {
        var server: ModelServer
        var model: String
    }

    private(set) var messages: [ModelChat.Message] = []
    private(set) var streaming = false
    private(set) var failure: String?
    /// The field has the keyboard: it stays focused when the page turns into the conversation.
    var editing = false
    /// The model questions go to; nil until one is picked or found.
    var choice: Choice? {
        didSet {
            guard let choice, choice != oldValue else { return }
            UserDefaults.standard.set("\(choice.server.id)\n\(choice.model)", forKey: "askModel")
        }
    }

    /// The last exchanges only: enough for a follow-up, never a growing transcript.
    private static let kept = 20
    /// Words gather here and reach the screen at most every 50 ms, however fast the model writes.
    @ObservationIgnored private var pending = ""
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped by each question and by Stop: an answer from before never reaches the screen.
    @ObservationIgnored private var generation = 0

    /// The models that can answer now: loaded ones first, on servers that answer.
    func choices(servers: [ModelServer], statuses: [String: ModelServerStatus]) -> [Choice] {
        servers.flatMap { server -> [Choice] in
            guard let status = statuses[server.id], status.reachable else { return [] }
            let loaded = status.loaded.map(\.name)
            let others = status.models.filter { !loaded.contains($0) }
            return (loaded + others).map { Choice(server: server, model: $0) }
        }
    }

    /// The model last used, if it can still answer, else the first that can.
    func resolve(_ choices: [Choice]) {
        if let choice, choices.contains(choice) { return }
        let saved = UserDefaults.standard.string(forKey: "askModel")?.split(separator: "\n", maxSplits: 1).map(String.init)
        if let saved, saved.count == 2, let match = choices.first(where: { $0.server.id == saved[0] && $0.model == saved[1] }) {
            choice = match
        } else {
            choice = choices.first
        }
    }

    /// `-ColAsk "question"` asks it once a model can answer, for screenshots of an answer.
    @ObservationIgnored private var askedOnLaunch = false

    func askOnLaunch() {
        guard !askedOnLaunch, choice != nil, let question = UserDefaults.standard.string(forKey: "ColAsk") else { return }
        askedOnLaunch = true
        ask(question)
    }

    func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !streaming, let choice else { return }
        failure = nil
        messages.append(.init(role: .user, text: text))
        if messages.count > Self.kept { messages.removeFirst(messages.count - Self.kept) }
        let conversation = messages
        messages.append(.init(role: .assistant, text: ""))
        streaming = true
        generation += 1
        let current = generation
        let token = choice.server.usesToken ? Keychain.token(for: choice.server.id) : nil
        task = Task { [weak self] in
            do {
                for try await piece in ModelChat.answer(conversation, model: choice.model, server: choice.server, token: token) {
                    guard let self, self.generation == current else { return }
                    self.receive(piece)
                }
            } catch is CancellationError {
            } catch {
                if self?.generation == current {
                    self?.failure = String(localized: "\(choice.server.name) did not answer.", bundle: .module)
                }
            }
            if self?.generation == current { self?.finish() }
        }
    }

    private func receive(_ piece: String) {
        pending += piece
        guard !flushing else { return }
        flushing = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.flush()
        }
    }

    private func flush() {
        flushing = false
        guard !pending.isEmpty, messages.last?.role == .assistant else { return }
        messages[messages.count - 1].text += pending
        pending = ""
    }

    private func finish() {
        flush()
        streaming = false
        task = nil
        // An answer that never came leaves no empty line behind, and no question without an answer.
        if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
            messages.removeLast()
            if messages.last?.role == .user { messages.removeLast() }
        }
    }

    func stop() {
        guard streaming else { return }
        generation += 1
        task?.cancel()
        finish()
    }

    func clear() {
        stop()
        messages = []
        failure = nil
    }

    var lastAnswer: String? {
        messages.last { $0.role == .assistant && !$0.text.isEmpty }.map { Self.shown($0.text).text }
    }

    func copyAnswer() {
        guard let answer = lastAnswer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }

    /// What an answer shows: a model that thinks aloud between `<think>` tags keeps that to itself, and while it is
    /// still thinking the answer says so.
    nonisolated static func shown(_ text: String) -> (text: String, thinking: Bool) {
        var shown = text
        while let open = shown.range(of: "<think>") {
            guard let close = shown.range(of: "</think>", range: open.upperBound..<shown.endIndex) else {
                return (String(shown[..<open.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), true)
            }
            shown.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return (shown.trimmingCharacters(in: .whitespacesAndNewlines), false)
    }

    /// An answer's Markdown, read for emphasis, code and links. The model writes it, and what it writes can be steered
    /// by text pasted into a question or by whoever runs the server: only a link to a web page stays a link. One to a
    /// file, a share, another app or one of Col's own actions shows as its words alone, with nothing to click.
    nonisolated static func markdown(_ text: String) -> AttributedString {
        var markdown = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let unsafe = markdown.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let link = run.link, !opensOnTheWeb(link) else { return nil }
            return run.range
        }
        for range in unsafe { markdown[range].link = nil }
        return markdown
    }

    /// Whether a link from an answer may be opened: a web page only.
    nonisolated static func opensOnTheWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}

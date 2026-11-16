import Foundation

/// A question Claude Code asks the user with its AskUserQuestion tool: a short header, the question and its options.
/// Claude Code asks for permission to show it, and its hook can answer instead of the terminal: `allow`, with the
/// questions as they were asked and `answers`, each question's text mapped to the labels chosen.
public struct AgentQuestion: Equatable, Sendable, Identifiable {
    public struct Option: Equatable, Sendable, Hashable {
        public var label: String
        public var detail: String?

        public init(label: String, detail: String? = nil) {
            self.label = label
            self.detail = detail
        }
    }

    public var id: String { question }
    public var question: String
    public var header: String?
    public var options: [Option]
    /// Several options can be chosen.
    public var multiSelect: Bool

    public init(question: String, header: String? = nil, options: [Option], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }

    /// The questions of an AskUserQuestion input; nil when it carries none in that shape, or one without options.
    public static func questions(from input: [String: JSONValue]?) -> [AgentQuestion]? {
        guard let list = input?["questions"]?.array, !list.isEmpty, list.count <= 8 else { return nil }
        var questions: [AgentQuestion] = []
        for item in list {
            guard let object = item.object, let text = object["question"]?.string, !text.isEmpty,
                  let options = object["options"]?.array, !options.isEmpty
            else { return nil }
            let parsed = options.compactMap { option -> Option? in
                guard let label = option.object?["label"]?.string, !label.isEmpty else { return nil }
                return Option(label: label, detail: option.object?["description"]?.string)
            }
            guard parsed.count == options.count, !questions.contains(where: { $0.question == text }) else { return nil }
            var multiSelect = false
            if case .bool(let flag)? = object["multiSelect"] { multiSelect = flag }
            questions.append(AgentQuestion(question: text, header: object["header"]?.string, options: parsed, multiSelect: multiSelect))
        }
        return questions
    }

    /// The input that answers the questions: the one Claude Code sent, with `answers` added. Nil unless every question
    /// has an answer among its own options, a single one where only one may be chosen. Several labels are joined with
    /// commas, as Claude Code reads them.
    public static func answering(_ input: [String: JSONValue], with choices: [String: [String]]) -> [String: JSONValue]? {
        guard let questions = questions(from: input) else { return nil }
        var answers: [String: JSONValue] = [:]
        for question in questions {
            let labels = question.options.map(\.label)
            // In the order the options are listed, whatever the order they were picked in.
            let chosen = labels.filter { (choices[question.question] ?? []).contains($0) }
            guard !chosen.isEmpty, chosen.count == Set(choices[question.question] ?? []).count,
                  question.multiSelect || chosen.count == 1
            else { return nil }
            answers[question.question] = .string(chosen.joined(separator: ", "))
        }
        var answered = input
        answered["answers"] = .object(answers)
        return answered
    }
}

/// Markdown read into the blocks a plan is made of: headings, paragraphs, list items, quotes, code and rules. Inline
/// marks (emphasis, code, links) stay in each block's text for the drawing to read.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// A list item: its marker as written ("•" for a bullet, "3." for a number), its text and its depth.
    case item(marker: String, text: String, depth: Int)
    case quote(String)
    case code(String)
    case rule
}

public enum MarkdownDocument {
    public static func blocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if var lines = code {
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    lines.append(raw)
                    code = lines
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                code = []
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
                continue
            }
            if ["---", "***", "___"].contains(trimmed.replacingOccurrences(of: " ", with: "")) {
                flush()
                blocks.append(.rule)
                continue
            }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            if let item = item(trimmed, depth: indent / 2) {
                flush()
                blocks.append(item)
                continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                let quoted = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if case .quote(let previous)? = blocks.last {
                    blocks[blocks.count - 1] = .quote(previous + " " + quoted)
                } else {
                    blocks.append(.quote(quoted))
                }
                continue
            }
            paragraph.append(trimmed)
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// The plan's title: its first heading, else its first line, in plain words.
    public static func title(_ text: String) -> String? {
        let blocks = blocks(text)
        let first = blocks.first { if case .heading = $0 { true } else { false } } ?? blocks.first
        let words: String? = switch first {
        case .heading(_, let text)?, .paragraph(let text)?, .quote(let text)?, .item(_, let text, _)?: text
        default: nil
        }
        return words.map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "") }
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces))
    }

    private static func item(_ line: String, depth: Int) -> MarkdownBlock? {
        for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
            var text = String(line.dropFirst(2))
            // Task lists: a box ticked or not.
            if text.hasPrefix("[ ] ") { return .item(marker: "☐", text: String(text.dropFirst(4)), depth: depth) }
            if text.lowercased().hasPrefix("[x] ") {
                text = String(text.dropFirst(4))
                return .item(marker: "☑", text: text, depth: depth)
            }
            return .item(marker: "•", text: text, depth: depth)
        }
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let after = line.dropFirst(digits.count)
        guard let mark = after.first, mark == "." || mark == ")", after.dropFirst().first == " " else { return nil }
        return .item(marker: digits + ".", text: String(after.dropFirst(2)), depth: depth)
    }
}

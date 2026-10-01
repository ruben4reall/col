import Foundation

/// A word the reader is expected to say, as the prompter shows it.
public struct ScriptWord: Equatable, Sendable {
    /// The word without its surrounding punctuation: "world" in "world.", "It's" in "It's".
    public let text: String
    /// Where the word sits in `Script.display`, in UTF-16 units, as TextKit counts.
    public let range: NSRange
    /// The line of the source the word comes from, starting at zero; blank lines count.
    public let paragraph: Int
}

/// A stretch of `Script.display` that the prompter draws differently.
public struct ScriptStyle: Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        /// A `# Heading` line: shown, never read aloud.
        case heading
        /// A `[cue]` for the reader, such as "pause" or "smile": shown quietly, never read aloud.
        case cue
        /// `**Words**` to stress: shown bold, read aloud.
        case emphasis
    }

    public let kind: Kind
    public let range: NSRange
}

/// A script as the reader wrote it, turned into the text the prompter shows and the words it expects to hear.
///
/// The markup is deliberately small and forgiving: `# ` starts a heading line, `[...]` is a cue and `**...**` is
/// emphasis. A marker that is not closed on its line stays as it was typed, so ordinary text never disappears.
public struct Script: Sendable {
    public let source: String
    /// The text the prompter shows: the source without its markup.
    public let display: String
    /// The words to be read, in order.
    public let words: [ScriptWord]
    public let styles: [ScriptStyle]

    /// True when there is nothing to read aloud (empty, or only headings and cues).
    public var isEmpty: Bool { words.isEmpty }

    public init(_ source: String) {
        self.source = source
        var builder = Builder()
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (index, line) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { builder.append("\n", kind: nil, paragraph: index) }
            if let heading = Self.heading(in: line) {
                builder.append(heading, kind: .heading, paragraph: index)
            } else {
                for segment in Self.segments(of: line) {
                    builder.append(segment.text, kind: segment.kind, paragraph: index)
                }
            }
        }
        display = builder.display
        words = builder.words
        styles = builder.styles
    }

    // MARK: Parsing

    /// The text of a heading line (`# Title`, `## Title`), or nil for any other line.
    private static func heading(in line: Substring) -> String? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.first == "#" else { return nil }
        let rest = trimmed.drop(while: { $0 == "#" })
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private struct Segment {
        var text: String
        var kind: ScriptStyle.Kind?
    }

    /// Splits a line into plain text, cues and emphasis.
    private static func segments(of line: Substring) -> [Segment] {
        var result: [Segment] = []
        var buffer = ""
        var emphasis = false
        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(Segment(text: buffer, kind: emphasis ? .emphasis : nil))
            buffer = ""
        }
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if character == "[", let close = line[next...].firstIndex(of: "]"), close > next {
                flush()
                result.append(Segment(text: String(line[next..<close]), kind: .cue))
                index = line.index(after: close)
                continue
            }
            if character == "*", next < line.endIndex, line[next] == "*" {
                let after = line.index(after: next)
                if emphasis {
                    flush()
                    emphasis = false
                    index = after
                    continue
                }
                if line[after...].contains("**") {
                    flush()
                    emphasis = true
                    index = after
                    continue
                }
            }
            buffer.append(character)
            index = next
        }
        flush()
        return result
    }

    /// Accumulates the display text, its styles and its words, counting UTF-16 offsets as it goes.
    private struct Builder {
        var display = ""
        var words: [ScriptWord] = []
        var styles: [ScriptStyle] = []
        private var offset = 0

        mutating func append(_ text: String, kind: ScriptStyle.Kind?, paragraph: Int) {
            let length = text.utf16.count
            if let kind, length > 0 { styles.append(ScriptStyle(kind: kind, range: NSRange(location: offset, length: length))) }
            if kind == nil || kind == .emphasis { collectWords(in: text, paragraph: paragraph) }
            display += text
            offset += length
        }

        /// Finds the words of a spoken stretch: runs of non-space characters, trimmed of the punctuation around them.
        private mutating func collectWords(in text: String, paragraph: Int) {
            var run: [(character: Character, offset: Int)] = []
            var position = offset
            func finishRun() {
                defer { run.removeAll(keepingCapacity: true) }
                guard var start = run.indices.first, var end = run.indices.last else { return }
                if run.count == 1, run[0].character == "&" {
                    words.append(ScriptWord(text: "&", range: NSRange(location: run[0].offset, length: 1), paragraph: paragraph))
                    return
                }
                while start <= end, !Self.isCore(run[start].character) { start += 1 }
                while end >= start, !Self.isCore(run[end].character),
                      !(run[end].character == "%" && end > start && run[end - 1].character.isNumber) { end -= 1 }
                guard start <= end else { return }
                let text = String(run[start...end].map(\.character))
                let from = run[start].offset
                let to = run[end].offset + run[end].character.utf16.count
                words.append(ScriptWord(text: text, range: NSRange(location: from, length: to - from), paragraph: paragraph))
            }
            for character in text {
                if character.isWhitespace {
                    finishRun()
                } else {
                    run.append((character, position))
                }
                position += character.utf16.count
            }
            finishRun()
        }

        private static func isCore(_ character: Character) -> Bool { character.isLetter || character.isNumber }
    }
}

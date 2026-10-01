import Foundation

/// Keeps the reader's place in the script from what the speech recogniser hears.
///
/// Each time the recogniser reports, the last few words it heard are aligned with the script around the current
/// place. The place only moves forward: re-reading a sentence, a recogniser revising its guess or a common word
/// said off script never pulls the script back or pushes it ahead. Jumping further ahead, when a paragraph was
/// skipped, takes a strong match of several words.
public struct VoiceTracker {
    public let script: Script
    private let transcript: Transcript
    /// The script as a sequence of comparable tokens, and the word each token belongs to.
    private let tokens: [String]
    private let tokenWord: [Int]
    /// Index in `tokens` of the next token to be read.
    private var position = 0

    /// How many of the latest heard tokens are aligned each time.
    static let window = 8
    /// How far ahead of the current place an ordinary match may land, in tokens.
    static let nearAhead = 12
    /// How far ahead a skipped passage may be found again, in tokens.
    static let farAhead = 600

    public init(script: Script, locale: Locale) {
        self.script = script
        let transcript = Transcript(locale: locale)
        self.transcript = transcript
        var tokens: [String] = []
        var tokenWord: [Int] = []
        for (index, word) in script.words.enumerated() {
            for token in transcript.tokens(ofWord: word.text) {
                tokens.append(token)
                tokenWord.append(index)
            }
        }
        self.tokens = tokens
        self.tokenWord = tokenWord
    }

    /// Index in `script.words` of the next word to read; `script.words.count` once everything has been read.
    public var wordIndex: Int {
        position < tokens.count ? tokenWord[position] : script.words.count
    }

    public var isFinished: Bool { position >= tokens.count }

    /// Aligns what the recogniser heard most recently, typically the utterance so far. Returns true when the
    /// place moved.
    @discardableResult
    public mutating func hear(_ text: String) -> Bool {
        let heard = Array(transcript.tokens(text).suffix(Self.window))
        guard let last = heard.last, !isFinished else { return false }

        // The best alignment around the current place, a little behind included: if the reader is re-reading,
        // the best match is behind and nothing moves.
        var best: (end: Int, score: Int)?
        let lower = max(0, position - Self.window)
        let upper = min(tokens.count - 1, position + Self.nearAhead)
        if lower <= upper {
            for end in lower...upper where Self.similar(tokens[end], last) {
                let score = alignment(heard, endingAt: end)
                if best == nil || score > best!.score || (score == best!.score && abs(end - position) < abs(best!.end - position)) {
                    best = (end, score)
                }
            }
        }
        if let best, best.end >= position, accepts(score: best.score, distance: best.end - position, heard: heard.count),
           best.end - position < 2 || evidence(heard, from: position, to: best.end) {
            return move(to: best.end + 1)
        }
        if let best, best.end < position, best.score >= 2 { return false }

        // Nothing near: maybe a passage was skipped. Only a strong match further ahead re-anchors.
        let farUpper = min(tokens.count - 1, position + Self.farAhead)
        guard upper < farUpper, heard.count >= 4 else { return false }
        let needed = max(4, Int((Double(heard.count) * 0.7).rounded(.up)))
        for end in (upper + 1)...farUpper where Self.similar(tokens[end], last) {
            if alignment(heard, endingAt: end) >= needed { return move(to: end + 1) }
        }
        return false
    }

    /// Sets the place by hand, to the start of a word.
    public mutating func jump(toWord index: Int) {
        let target = max(0, min(index, script.words.count))
        position = tokenWord.firstIndex(where: { $0 >= target }) ?? tokens.count
    }

    private mutating func move(to newPosition: Int) -> Bool {
        guard newPosition > position else { return false }
        position = min(newPosition, tokens.count)
        return true
    }

    /// A single matching word is only trusted when it is the very next one; two or more in order anywhere near.
    private func accepts(score: Int, distance: Int, heard: Int) -> Bool {
        if score >= 2 { return true }
        return distance <= 1 && heard <= 2
    }

    /// True when at least one word heard before the last lines up with the words being skipped, `from` up to `end`.
    /// Without it, a match made of words already read plus one word said off script would jump ahead.
    private func evidence(_ heard: [String], from start: Int, to end: Int) -> Bool {
        guard start < end else { return true }
        let skipped = tokens[start..<end]
        return heard.dropLast().contains { word in skipped.contains { Self.similar($0, word) } }
    }

    /// How many of the heard tokens line up, in order, with the script tokens that end at `end`, the last heard
    /// token being matched to `end` itself. Gaps are allowed on both sides: a misheard word, a word skipped.
    private func alignment(_ heard: [String], endingAt end: Int) -> Int {
        let earlier = heard.dropLast()
        guard !earlier.isEmpty else { return 1 }
        let start = max(0, end - earlier.count - 3)
        let scriptSlice = Array(tokens[start..<end])
        let heardSlice = Array(earlier)
        // Longest common subsequence, with the fuzzy comparison.
        var previous = [Int](repeating: 0, count: scriptSlice.count + 1)
        var current = previous
        for heardToken in heardSlice {
            for (column, scriptToken) in scriptSlice.enumerated() {
                current[column + 1] = Self.similar(scriptToken, heardToken)
                    ? previous[column] + 1
                    : max(previous[column + 1], current[column])
            }
            swap(&previous, &current)
        }
        return 1 + (previous.last ?? 0)
    }

    /// Equal, or close enough to be the same word misheard or cut short by a recogniser still listening.
    static func similar(_ written: String, _ heard: String) -> Bool {
        if written == heard { return true }
        let a = Array(written), b = Array(heard)
        if b.count >= 4, a.count > b.count, written.hasPrefix(heard) { return true }
        let shortest = min(a.count, b.count)
        guard shortest >= 4 else { return false }
        let allowed = max(a.count, b.count) >= 9 ? 2 : 1
        guard abs(a.count - b.count) <= allowed else { return false }
        return editDistance(a, b, limit: allowed) <= allowed
    }

    /// Levenshtein distance, giving up once it exceeds `limit`.
    private static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMinimum = min(rowMinimum, current[j])
            }
            if rowMinimum > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

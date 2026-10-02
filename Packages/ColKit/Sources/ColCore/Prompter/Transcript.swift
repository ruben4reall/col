import Foundation

/// Turns written or recognised words into comparable tokens: lower case, without accents or punctuation, with
/// contractions expanded and numbers spelled out in the script's language, so that "Don't", "25%" and "Café" meet
/// "do not", "twenty-five percent" and "cafe".
public final class Transcript {
    public let locale: Locale
    private let spellOut: NumberFormatter
    private let language: String

    public init(locale: Locale) {
        self.locale = locale
        language = locale.language.languageCode?.identifier ?? "en"
        spellOut = NumberFormatter()
        spellOut.numberStyle = .spellOut
        spellOut.locale = locale
    }

    /// Tokens of something heard, without the fillers people say between words.
    public func tokens(_ text: String) -> [String] {
        words(in: text).flatMap(normalize).filter { !Self.fillers.contains($0) }
    }

    /// Tokens of one written word of the script. Fillers are kept: if the script says "um", so be it.
    public func tokens(ofWord word: String) -> [String] {
        normalize(word)
    }

    private func words(in text: String) -> [Substring] {
        text.split(whereSeparator: { $0.isWhitespace })
    }

    /// One written word to zero or more tokens.
    private func normalize<S: StringProtocol>(_ word: S) -> [String] {
        let folded = word
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
        if folded == "&" { return [Self.and[language] ?? "and"] }
        // Split on everything that is not a letter, a digit, an apostrophe, a decimal separator or a percent sign,
        // then deal with each piece.
        var tokens: [String] = []
        for piece in folded.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "." || $0 == "," || $0 == "%") }) {
            tokens += normalizePiece(String(piece))
        }
        return tokens
    }

    private func normalizePiece(_ raw: String) -> [String] {
        var piece = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'.,"))
        guard !piece.isEmpty else { return [] }
        var suffix: [String] = []
        if piece.hasSuffix("%") {
            piece.removeLast()
            suffix = (Self.percent[language] ?? "percent").split(separator: " ").map(String.init)
        }
        if let number = number(in: piece) { return number + suffix }
        if language == "en", let expanded = Self.contractions[piece] { return expanded + suffix }
        // Other apostrophes separate an elision from its word ("l'homme", "j'ai") or a possessive ("Ruben's").
        let parts = piece.split(separator: "'").map { String($0).filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty }
        return parts + suffix
    }

    /// A number written in digits, spelled out in the transcript's language and split into words.
    private func number(in piece: String) -> [String]? {
        guard piece.first?.isNumber == true else { return nil }
        let plain = piece.replacingOccurrences(of: ",", with: "")
        guard let value = Double(plain), value.isFinite, value < 1_000_000_000 else {
            return piece.filter { $0.isNumber }.isEmpty ? nil : [piece.filter { $0.isNumber }]
        }
        guard let spelled = spellOut.string(from: NSNumber(value: value)) else { return nil }
        return spelled
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            .lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// Sounds that carry no words, in the languages people most often read scripts in.
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhm", "erm", "er", "ah", "hmm", "mm", "mhm",
        "euh", "heu", "hum", "ehm", "eh", "ahm", "aeh", "aehm", "ah",
    ]

    static let and: [String: String] = ["en": "and", "fr": "et", "es": "y", "de": "und", "pt": "e", "it": "e", "nl": "en"]
    static let percent: [String: String] = [
        "en": "percent", "fr": "pour cent", "es": "por ciento", "de": "prozent", "pt": "por cento", "it": "per cento", "nl": "procent",
    ]

    static let contractions: [String: [String]] = [
        "don't": ["do", "not"], "doesn't": ["does", "not"], "didn't": ["did", "not"], "can't": ["can", "not"],
        "cannot": ["can", "not"], "won't": ["will", "not"], "wouldn't": ["would", "not"], "shouldn't": ["should", "not"],
        "couldn't": ["could", "not"], "isn't": ["is", "not"], "aren't": ["are", "not"], "wasn't": ["was", "not"],
        "weren't": ["were", "not"], "haven't": ["have", "not"], "hasn't": ["has", "not"], "hadn't": ["had", "not"],
        "i'm": ["i", "am"], "you're": ["you", "are"], "we're": ["we", "are"], "they're": ["they", "are"],
        "it's": ["it", "is"], "that's": ["that", "is"], "there's": ["there", "is"], "here's": ["here", "is"],
        "what's": ["what", "is"], "who's": ["who", "is"], "he's": ["he", "is"], "she's": ["she", "is"],
        "let's": ["let", "us"], "i've": ["i", "have"], "you've": ["you", "have"], "we've": ["we", "have"],
        "they've": ["they", "have"], "i'll": ["i", "will"], "you'll": ["you", "will"], "we'll": ["we", "will"],
        "they'll": ["they", "will"], "it'll": ["it", "will"], "i'd": ["i", "would"], "you'd": ["you", "would"],
        "we'd": ["we", "would"], "they'd": ["they", "would"], "gonna": ["going", "to"], "wanna": ["want", "to"],
    ]
}

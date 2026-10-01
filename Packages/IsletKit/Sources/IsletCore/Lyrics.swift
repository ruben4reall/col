import Foundation

/// A word sung at a moment of its line, for lyrics timed word by word.
public struct LyricWord: Equatable, Sendable {
    public var time: TimeInterval
    public var text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

/// One line of lyrics, and when it starts. An empty text marks a pause: an instrumental passage between two lines.
public struct LyricLine: Equatable, Sendable, Identifiable {
    public var time: TimeInterval
    public var text: String
    /// The timing of each word, when the lyrics have it.
    public var words: [LyricWord]

    public init(time: TimeInterval, text: String, words: [LyricWord] = []) {
        self.time = time
        self.text = text
        self.words = words
    }

    /// Lines are told apart by their start; two lines never start at the same moment.
    public var id: TimeInterval { time }

    public var isPause: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// The lyrics of a track: timed lines, or plain text when only that exists.
public struct Lyrics: Equatable, Sendable {
    public var lines: [LyricLine]
    /// False for plain lyrics, which have no timing: they are shown, never followed.
    public var isSynced: Bool

    public init(lines: [LyricLine], isSynced: Bool) {
        self.lines = lines
        self.isSynced = isSynced
    }

    /// A pause longer than this between two lines shows as a pause of its own (three dots that breathe).
    public static let pauseThreshold: TimeInterval = 5

    /// Reads LRC: `[mm:ss.xx] text` lines, several timestamps on one line, an `[offset:±ms]` tag, metadata tags
    /// (ignored) and word timing in angle brackets (`<mm:ss.xx> word`). Returns nil when no line is timed.
    public static func parse(lrc: String) -> Lyrics? {
        var offset: TimeInterval = 0
        var lines: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = timestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"), let value = Double(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) {
                    // A positive offset shows the lyrics sooner.
                    offset = value / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }
            let (text, words) = wordTiming(String(rest))
            for time in times {
                lines.append(LyricLine(time: time, text: text, words: words))
            }
        }
        guard !lines.isEmpty else { return nil }
        lines = lines.map { line in
            var line = line
            line.time = max(0, line.time - offset)
            line.words = line.words.map { LyricWord(time: max(0, $0.time - offset), text: $0.text) }
            return line
        }
        lines.sort { $0.time < $1.time }
        // Two lines at the same moment: keep the first.
        var unique: [LyricLine] = []
        for line in lines where unique.last?.time != line.time { unique.append(line) }
        return Lyrics(lines: withPauses(unique), isSynced: true)
    }

    /// Plain lyrics, one line per line, without timing.
    public static func plain(_ text: String) -> Lyrics? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { !$0.isEmpty }) else { return nil }
        return Lyrics(lines: lines.enumerated().map { LyricLine(time: TimeInterval($0.offset), text: $0.element) }, isSynced: false)
    }

    /// The line being sung at a position of the track: the last one that has started. Nil before the first.
    public func index(at position: TimeInterval) -> Int? {
        guard isSynced, let first = lines.first, position >= first.time else { return nil }
        var low = 0, high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].time <= position { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// When the line on show next changes, after a position: the start of the next line.
    public func nextChange(after position: TimeInterval) -> TimeInterval? {
        guard isSynced else { return nil }
        return lines.first { $0.time > position }?.time
    }

    // MARK: Reading

    /// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx`, and `hh:mm:ss.xx` for long tracks.
    static func timestamp<S: StringProtocol>(_ text: S) -> TimeInterval? {
        let parts = text.split(separator: ":")
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        var total: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            guard let value = isLast ? Double(part.replacingOccurrences(of: ",", with: ".")) : Double(part),
                  value >= 0, isLast || value == value.rounded()
            else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// Takes word timing out of a line: `<00:12.10> Hello <00:12.60> world` reads "Hello world".
    static func wordTiming(_ text: String) -> (String, [LyricWord]) {
        guard text.contains("<") else { return (text.trimmingCharacters(in: .whitespaces), []) }
        var words: [LyricWord] = []
        var plain = ""
        var rest = Substring(text)
        var current: TimeInterval?
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            let before = rest[..<open]
            if let current, !before.trimmingCharacters(in: .whitespaces).isEmpty {
                words.append(LyricWord(time: current, text: before.trimmingCharacters(in: .whitespaces)))
            }
            plain += before
            current = timestamp(rest[rest.index(after: open)..<close])
            rest = rest[rest.index(after: close)...]
        }
        if let current, !rest.trimmingCharacters(in: .whitespaces).isEmpty {
            words.append(LyricWord(time: current, text: rest.trimmingCharacters(in: .whitespaces)))
        }
        plain += rest
        let collapsed = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (collapsed, words)
    }

    /// A long gap after a line ends becomes a pause line of its own, so the view can show that the song goes on.
    static func withPauses(_ lines: [LyricLine]) -> [LyricLine] {
        var result: [LyricLine] = []
        // An introduction before the first words.
        if let first = lines.first, first.time > pauseThreshold, !first.isPause {
            result.append(LyricLine(time: 0, text: ""))
        }
        for (index, line) in lines.enumerated() {
            result.append(line)
            guard !line.isPause, index + 1 < lines.count else { continue }
            let next = lines[index + 1]
            // A sung line lasts about as long as its words take, at most eight seconds.
            let sung = line.words.last.map { $0.time + 1 } ?? line.time + min(8, max(2, Double(line.text.count) * 0.09))
            if next.time - sung > pauseThreshold, !next.isPause {
                result.append(LyricLine(time: sung, text: ""))
            }
        }
        return result
    }
}

/// What lyrics lookups need to know about a track, and how the answer is cached.
public struct LyricsQuery: Equatable, Hashable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval

    public init(title: String, artist: String, album: String, duration: TimeInterval) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    /// Players add noise to titles that the lyrics never have: "(Remastered 2011)", "- Live", "[Explicit]".
    public var cleanTitle: String {
        var title = self.title
        for pattern in [#"\s*[\(\[][^\)\]]*(remaster|live|explicit|version|edit|mono|stereo|deluxe|bonus)[^\)\]]*[\)\]]"#,
                        #"\s+-\s+.*(remaster|live|version|edit|mono|stereo).*$"#] {
            title = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// The main artist, without featured ones: "Gradur feat. Heuss" reads "Gradur".
    public var mainArtist: String {
        let separators = [" feat. ", " feat ", " ft. ", " ft ", " featuring ", ", ", " & ", " x ", " X "]
        var artist = self.artist
        for separator in separators {
            if let range = artist.range(of: separator, options: .caseInsensitive) { artist = String(artist[..<range.lowerBound]) }
        }
        return artist.trimmingCharacters(in: .whitespaces)
    }

    /// A key for the cache, the same for the same track whatever player reports it.
    public var cacheKey: String {
        "\(mainArtist.lowercased())\u{1F}\(cleanTitle.lowercased())\u{1F}\(Int(duration.rounded()))"
    }

    /// True when a found track is this one: same length within two seconds when both lengths are known.
    public func matches(duration found: TimeInterval?) -> Bool {
        guard let found, duration > 0 else { return true }
        return abs(found - duration) <= 2
    }
}

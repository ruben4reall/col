import Foundation

/// A line timed word by word, ready to be filled as it is sung: the words as they show, each with the moments its
/// letters light up. Built from the line's text and the timing of its words or syllables, so a word sung in several
/// pieces (`<00:01.00>Hel<00:01.20>lo`) fills as one word.
public struct KaraokeLine: Equatable, Sendable {
    /// A moment of a word, and how much of it is sung by then, from 0 to 1.
    public struct Stop: Equatable, Sendable {
        public var time: TimeInterval
        public var fraction: Double

        public init(time: TimeInterval, fraction: Double) {
            self.time = time
            self.fraction = fraction
        }
    }

    public struct Word: Equatable, Sendable {
        public var text: String
        /// From the first letter at 0 to the last at 1, in order of time.
        public var stops: [Stop]
        /// False between two pieces of text shown together, as in lyrics without spaces (Japanese, Chinese).
        public var spaceAfter: Bool

        public init(text: String, stops: [Stop], spaceAfter: Bool = true) {
            self.text = text
            self.stops = stops
            self.spaceAfter = spaceAfter
        }

        public var start: TimeInterval { stops.first?.time ?? 0 }
        public var end: TimeInterval { stops.last?.time ?? 0 }

        /// How much of the word is lit at a moment of the song: 0 before it starts, 1 once it is sung.
        public func fill(at time: TimeInterval) -> Double {
            guard let first = stops.first, let last = stops.last, time.isFinite, time >= first.time else { return 0 }
            if time == first.time { return first.fraction }
            if time >= last.time { return 1 }
            for (from, to) in zip(stops, stops.dropFirst()) where time < to.time {
                let span = to.time - from.time
                guard span > 0 else { return to.fraction }
                return from.fraction + (to.fraction - from.fraction) * (time - from.time) / span
            }
            return 1
        }
    }

    public var words: [Word]

    /// How long the last word of a line lasts when the lyrics do not say: about as long as its letters take, held a
    /// little, never more than a second and a half.
    static func lastWordLength(_ text: String) -> TimeInterval {
        min(1.5, max(0.4, Double(text.count) * 0.1))
    }

    /// Nil when the line has no word timing, or when its timed words do not spell its text: such a line is shown
    /// whole, as lines without word timing are. `next` is when the next line starts, which the last word never passes.
    public init?(line: LyricLine, next: TimeInterval? = nil) {
        guard !line.words.isEmpty, !line.isPause else { return nil }
        let shown = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !shown.isEmpty else { return nil }

        // Each timed piece lasts until the next one starts; the last until the line closes.
        // Letters are counted word by word: joined, two words can fuse into one letter (two flags, an Indic
        // consonant after a virama) and the counts would no longer agree.
        var pieces = line.words.map { (start: $0.time, end: $0.time, letters: Self.letters($0.text)) }
        for index in pieces.indices.dropLast() { pieces[index].end = pieces[index + 1].start }
        let last = pieces[pieces.count - 1]
        var lastEnd = line.end ?? last.start + Self.lastWordLength(String(last.letters))
        if let next, next > last.start { lastEnd = min(lastEnd, next) }
        pieces[pieces.count - 1].end = max(lastEnd, last.start)

        // Lyrics written without spaces (Japanese, Chinese) are one long run of letters: each timed piece shows on its
        // own, with no space after it, so the line can wrap between them.
        if shown.count == 1, pieces.count >= 3, pieces.flatMap(\.letters) == Array(shown[0]) {
            words = pieces.enumerated().map { index, piece in
                Word(text: String(piece.letters), stops: [Stop(time: piece.start, fraction: 0), Stop(time: piece.end, fraction: 1)],
                     spaceAfter: index == pieces.count - 1)
            }
            return
        }

        // The timed letters must spell the end of the line. Letters before them are sung from the line's start.
        let timed = pieces.flatMap(\.letters)
        let all = shown.flatMap { Array($0) }
        guard !timed.isEmpty, timed.count <= all.count, Array(all.suffix(timed.count)) == timed else { return nil }
        let untimed = all.count - timed.count
        if untimed > 0 {
            pieces.insert((start: min(line.time, pieces[0].start), end: pieces[0].start, letters: Array(all.prefix(untimed))), at: 0)
        }

        // When each letter of the line starts and ends: spread evenly over its piece.
        var moments: [(start: TimeInterval, end: TimeInterval)] = []
        for piece in pieces {
            let count = Double(piece.letters.count)
            for index in piece.letters.indices {
                let span = piece.end - piece.start
                moments.append((piece.start + span * Double(index) / count, piece.start + span * Double(index + 1) / count))
            }
        }

        // One moment per shown letter, or the timing does not belong to this text.
        guard moments.count == shown.reduce(0, { $0 + $1.count }) else { return nil }
        var result: [Word] = []
        var offset = 0
        for word in shown {
            let count = word.count
            var stops: [Stop] = []
            for index in 0..<count {
                let moment = moments[offset + index]
                stops.append(Stop(time: moment.start, fraction: Double(index) / Double(count)))
                stops.append(Stop(time: moment.end, fraction: Double(index + 1) / Double(count)))
            }
            offset += count
            result.append(Word(text: word, stops: Self.simplified(stops)))
        }
        words = result
    }

    /// The letters of a piece of text, word by word, without the spaces.
    static func letters(_ text: String) -> [Character] {
        text.split(whereSeparator: \.isWhitespace).flatMap { Array($0) }
    }

    public init(words: [Word]) {
        self.words = words
    }

    /// Keeps only the stops where the pace changes: letters of one piece share a pace, so a word keeps a stop at
    /// each change of piece, and its start and end.
    static func simplified(_ stops: [Stop]) -> [Stop] {
        var result: [Stop] = []
        for stop in stops {
            if let last = result.last, stop.time < last.time { continue }
            if let last = result.last, stop.time == last.time {
                result[result.count - 1].fraction = max(last.fraction, stop.fraction)
                continue
            }
            if result.count >= 2 {
                let a = result[result.count - 2], b = result[result.count - 1]
                let paceBefore = (b.fraction - a.fraction) / (b.time - a.time)
                let paceNow = (stop.fraction - b.fraction) / (stop.time - b.time)
                if abs(paceBefore - paceNow) < 1e-9 { result[result.count - 1] = stop; continue }
            }
            result.append(stop)
        }
        if result.count == 1 { result.append(Stop(time: result[0].time, fraction: 1)) }
        return result
    }

    /// When the line is fully sung.
    public var end: TimeInterval { words.last?.end ?? 0 }

    /// How much of each word is lit at a moment of the song.
    public func fills(at time: TimeInterval) -> [Double] {
        words.map { $0.fill(at: time) }
    }
}

extension Lyrics {
    /// The same lyrics, shown later by `offset` seconds (sooner when negative): a track whose lyrics run ahead of the
    /// voice, or behind it.
    public func shifted(by offset: TimeInterval) -> Lyrics {
        guard offset != 0, offset.isFinite, isSynced else { return self }
        var copy = self
        copy.lines = lines.map { line in
            var line = line
            line.time += offset
            line.words = line.words.map { LyricWord(time: $0.time + offset, text: $0.text) }
            line.end = line.end.map { $0 + offset }
            return line
        }
        return copy
    }

    /// The karaoke of a line, or nil when it is not timed word by word.
    public func karaoke(at index: Int) -> KaraokeLine? {
        guard isSynced, lines.indices.contains(index) else { return nil }
        let next = lines.indices.contains(index + 1) ? lines[index + 1].time : nil
        return KaraokeLine(line: lines[index], next: next)
    }

    /// True when at least one line is timed word by word.
    public var hasWordTiming: Bool { isSynced && lines.contains { !$0.words.isEmpty } }

    /// The lines around the one being sung, for views that show a few: `before` lines above it and `after` below.
    /// Before the first line, the first ones, as lines to come.
    public func neighbourhood(of current: Int?, before: Int, after: Int) -> Range<Int> {
        guard !lines.isEmpty else { return 0..<0 }
        guard let current, lines.indices.contains(current) else { return 0..<min(lines.count, after + 1) }
        return max(0, current - before)..<min(lines.count, current + after + 1)
    }
}

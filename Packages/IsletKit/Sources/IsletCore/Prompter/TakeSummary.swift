import Foundation

/// What a take looked like once it is over: the coach's summary.
public struct TakeSummary: Equatable, Sendable {
    public var duration: TimeInterval
    public var wordsRead: Int
    public var totalWords: Int
    /// Longest time without progress in the script, in seconds.
    public var longestPause: TimeInterval
    /// Hesitations such as "um" or "euh" the recogniser reported.
    public var fillers: Int

    public var averageWordsPerMinute: Double {
        duration > 0 ? Double(wordsRead) / duration * 60 : 0
    }

    /// The reader's own pace, to roll the script at next time: the average, to the nearest 5 words a minute and within
    /// `range`. Nil after a take too short to say (under 20 seconds or 30 words).
    public func suggestedPace(range: ClosedRange<Double>) -> Double? {
        guard duration >= 20, wordsRead >= 30 else { return nil }
        let rounded = (averageWordsPerMinute / 5).rounded() * 5
        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    /// Share of the script that was read, from 0 to 1.
    public var coverage: Double {
        totalWords > 0 ? Double(wordsRead) / Double(totalWords) : 0
    }
}

/// Collects a take as it happens.
public struct TakeRecorder: Sendable {
    private let totalWords: Int
    private let start: Date
    private var furthest = 0
    private var lastProgress: Date
    private var longestPause: TimeInterval = 0
    private var fillers = 0

    public init(totalWords: Int, start: Date) {
        self.totalWords = totalWords
        self.start = start
        lastProgress = start
    }

    public mutating func record(wordIndex: Int, at time: Date) {
        guard wordIndex > furthest else { return }
        longestPause = max(longestPause, time.timeIntervalSince(lastProgress))
        furthest = wordIndex
        lastProgress = time
    }

    /// Counts the fillers in a final result. Partial results repeat themselves: pass only final ones.
    public mutating func heard(_ finalText: String) {
        fillers += finalText
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .filter { Transcript.fillers.contains($0.lowercased()) }
            .count
    }

    public func finish(at time: Date) -> TakeSummary {
        TakeSummary(
            duration: max(0, time.timeIntervalSince(start)),
            wordsRead: furthest,
            totalWords: totalWords,
            longestPause: longestPause,
            fillers: fillers
        )
    }
}

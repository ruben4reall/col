import Foundation
import Testing
@testable import ColCore

struct KaraokeTests {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    @Test func enhancedLyricsKeepTheEndOfTheLine() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:10.00] <00:10.00> Hold <00:10.50> on <00:11.00> tight <00:12.20>\n[00:14.00] Next"))
        let line = try #require(lyrics.lines.first { !$0.isPause })
        #expect(line.text == "Hold on tight")
        #expect(line.words.map(\.text) == ["Hold", "on", "tight"])
        #expect(line.end == 12.2)
    }

    @Test func plainLinesAreReadAsBefore() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:01.00]Plain line\n[00:03.00]Another one"))
        #expect(lyrics.lines.allSatisfy { $0.words.isEmpty && $0.end == nil })
        #expect(!lyrics.hasWordTiming)
        #expect(lyrics.karaoke(at: 0) == nil)
    }

    @Test func aChorusSungAgainKeepsItsWordsOnlyWhereTheyBelong() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:05.00][00:30.00]<00:05.10> La <00:05.60> la"))
        let sung = lyrics.lines.filter { !$0.isPause }
        #expect(sung.map(\.time) == [5, 30])
        #expect(sung[0].words.count == 2)
        // The words were timed for the first chorus: the second is followed line by line.
        #expect(sung[1].words.isEmpty)
    }

    @Test func wordsOutOfOrderAreNotFollowed() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:05.00]<00:06.00> late <00:05.10> early"))
        #expect(lyrics.lines.first { !$0.isPause }?.words.isEmpty == true)
    }

    @Test func eachWordFillsWhileItIsSung() throws {
        let line = LyricLine(time: 10, text: "Hold on tight", words: [
            LyricWord(time: 10, text: "Hold"), LyricWord(time: 10.5, text: "on"), LyricWord(time: 11, text: "tight"),
        ], end: 12)
        let karaoke = try #require(KaraokeLine(line: line, next: 14))
        #expect(karaoke.words.map(\.text) == ["Hold", "on", "tight"])
        #expect(karaoke.fills(at: 9.9) == [0, 0, 0])
        #expect(close(karaoke.words[0].fill(at: 10.25), 0.5))
        #expect(karaoke.fills(at: 10.5) == [1, 0, 0])
        #expect(close(karaoke.words[2].fill(at: 11.5), 0.5))
        #expect(karaoke.fills(at: 12) == [1, 1, 1])
        #expect(karaoke.end == 12)
    }

    @Test func aWordSungInPiecesFillsAsOneWord() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:01.00]<00:01.00>Hel<00:01.30>lo <00:02.00>world <00:03.00>"))
        let karaoke = try #require(lyrics.karaoke(at: 0))
        #expect(karaoke.words.map(\.text) == ["Hello", "world"])
        let hello = karaoke.words[0]
        // "Hel" takes 0.3 s for three letters of five, "lo" the next 0.7 s for two.
        #expect(close(hello.fill(at: 1.3), 0.6))
        #expect(close(hello.fill(at: 1.65), 0.8))
        #expect(hello.fill(at: 2) == 1)
        #expect(karaoke.words[1].start == 2)
    }

    @Test func untimedLettersAtTheStartAreSungFromTheLinesStart() throws {
        let line = LyricLine(time: 4, text: "Oh my love", words: [LyricWord(time: 5, text: "my"), LyricWord(time: 5.5, text: "love")])
        let karaoke = try #require(KaraokeLine(line: line, next: 8))
        #expect(karaoke.words.map(\.text) == ["Oh", "my", "love"])
        #expect(karaoke.words[0].start == 4)
        #expect(karaoke.words[0].end == 5)
        // Without an end time, the last word lasts as its letters take, never past the next line.
        #expect(close(karaoke.words[2].end, 5.9))
    }

    @Test func theLastWordNeverRunsIntoTheNextLine() throws {
        let line = LyricLine(time: 0, text: "Go", words: [LyricWord(time: 1, text: "Go")])
        #expect(KaraokeLine(line: line, next: 1.2)?.end == 1.2)
        #expect(KaraokeLine(line: line, next: nil)?.end == 1.4)
    }

    @Test func timingThatDoesNotSpellTheLineIsLeftOut() {
        let line = LyricLine(time: 0, text: "Hello world", words: [LyricWord(time: 0, text: "Goodbye"), LyricWord(time: 1, text: "world")])
        #expect(KaraokeLine(line: line) == nil)
        #expect(KaraokeLine(line: LyricLine(time: 0, text: "", words: [LyricWord(time: 0, text: "x")])) == nil)
        #expect(KaraokeLine(line: LyricLine(time: 0, text: "Plain")) == nil)
    }

    @Test func linesWithoutSpacesShowEachPieceOnItsOwn() throws {
        let line = LyricLine(time: 0, text: "夜に駆ける", words: [
            LyricWord(time: 0, text: "夜"), LyricWord(time: 0.4, text: "に"), LyricWord(time: 0.8, text: "駆"), LyricWord(time: 1.2, text: "ける"),
        ], end: 2)
        let karaoke = try #require(KaraokeLine(line: line))
        #expect(karaoke.words.map(\.text) == ["夜", "に", "駆", "ける"])
        #expect(karaoke.words.dropLast().allSatisfy { !$0.spaceAfter })
        #expect(zip(karaoke.fills(at: 0.6), [1, 0.5, 0, 0]).allSatisfy { close($0, $1) })
    }

    @Test func shiftingMovesEveryTime() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:10.00]<00:10.00> a <00:11.00> b <00:12.00>\n[00:20.00] c"))
        let later = lyrics.shifted(by: 1.5)
        let first = try #require(later.lines.first { !$0.isPause })
        #expect(first.time == 11.5)
        #expect(first.words.map(\.time) == [11.5, 12.5])
        #expect(first.end == 13.5)
        #expect(lyrics.shifted(by: -0.5).index(at: 9.6) == lyrics.index(at: 10.1))
        #expect(lyrics.shifted(by: 0) == lyrics)
        #expect(lyrics.shifted(by: .nan) == lyrics)
        let plain = try #require(Lyrics.plain("a\nb"))
        #expect(plain.shifted(by: 3) == plain)
    }

    @Test func theNeighbourhoodStaysInsideTheLyrics() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:01.00]a\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d"))
        #expect(lyrics.neighbourhood(of: nil, before: 1, after: 2) == 0..<3)
        #expect(lyrics.neighbourhood(of: 0, before: 1, after: 2) == 0..<3)
        #expect(lyrics.neighbourhood(of: 2, before: 1, after: 2) == 1..<4)
        #expect(lyrics.neighbourhood(of: 9, before: 1, after: 2) == 0..<3)
        #expect(Lyrics(lines: [], isSynced: true).neighbourhood(of: 0, before: 1, after: 1).isEmpty)
    }
}

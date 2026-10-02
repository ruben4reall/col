import Foundation
import Testing
@testable import ColCore

struct LyricsTests {
    @Test func readsTimedLinesInOrder() throws {
        let lyrics = try #require(Lyrics.parse(lrc: """
        [ar:Someone]
        [ti:A Song]
        [00:12.50]Second line
        [00:01.00]First line
        [00:20.00]
        """))
        #expect(lyrics.isSynced)
        // The first line is sung in about two seconds: the nine that follow are a pause.
        #expect(lyrics.lines.map(\.text) == ["First line", "", "Second line", ""])
        #expect(lyrics.lines.map(\.time) == [1, 3, 12.5, 20])
    }

    @Test func oneLineCanCarrySeveralTimes() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:05.00][00:30.00]Chorus\n[00:10.00]Verse"))
        #expect(lyrics.lines.filter { !$0.isPause }.map(\.text) == ["Chorus", "Verse", "Chorus"])
    }

    @Test func anOffsetShowsTheLinesSooner() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[offset:+500]\n[00:02.00]Hello"))
        #expect(lyrics.lines.first?.time == 1.5)
    }

    @Test func wordTimingIsKeptAndTheTextStaysClean() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:12.00]<00:12.10> Hello <00:12.60> world"))
        let line = try #require(lyrics.lines.first { !$0.isPause })
        #expect(line.text == "Hello world")
        #expect(line.words == [LyricWord(time: 12.1, text: "Hello"), LyricWord(time: 12.6, text: "world")])
    }

    @Test func longGapsBecomePauses() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:10.00]Late start\n[00:12.00]Close\n[00:40.00]After a solo"))
        // The introduction, then the solo between the second and the third line.
        #expect(lyrics.lines.map(\.isPause) == [true, false, false, true, false])
        #expect(lyrics.lines.first?.time == 0)
    }

    @Test func findsTheLineBeingSung() throws {
        let lyrics = try #require(Lyrics.parse(lrc: "[00:01.00]a\n[00:03.00]b\n[00:05.00]c"))
        #expect(lyrics.index(at: 0.5) == nil)
        #expect(lyrics.index(at: 1) == 0)
        #expect(lyrics.index(at: 4.9) == 1)
        #expect(lyrics.index(at: 500) == 2)
        #expect(lyrics.nextChange(after: 3) == 5)
        #expect(lyrics.nextChange(after: 5) == nil)
    }

    @Test func readsEveryTimestampForm() {
        #expect(Lyrics.timestamp("01:02") == 62)
        #expect(Lyrics.timestamp("01:02.5") == 62.5)
        #expect(Lyrics.timestamp("01:02.250") == 62.25)
        #expect(Lyrics.timestamp("1:01:02.00") == 3662)
        #expect(Lyrics.timestamp("ar:Someone") == nil)
        #expect(Lyrics.timestamp("01:xx") == nil)
    }

    @Test func plainLyricsAreShownButNeverFollowed() throws {
        let lyrics = try #require(Lyrics.plain("One\nTwo"))
        #expect(!lyrics.isSynced)
        #expect(lyrics.index(at: 10) == nil)
        #expect(Lyrics.plain(" \n ") == nil)
        #expect(Lyrics.parse(lrc: "no timing at all") == nil)
    }

    @Test func queriesLeaveThePlayersNoiseOut() {
        let query = LyricsQuery(title: "Terrasser (Remastered 2020)", artist: "Gradur feat. Heuss", album: "", duration: 181)
        #expect(query.cleanTitle == "Terrasser")
        #expect(query.mainArtist == "Gradur")
        #expect(query.cacheKey == LyricsQuery(title: "terrasser", artist: "GRADUR", album: "x", duration: 181.2).cacheKey)
        #expect(query.matches(duration: 182.5))
        #expect(!query.matches(duration: 190))
        #expect(query.matches(duration: nil))
    }
}

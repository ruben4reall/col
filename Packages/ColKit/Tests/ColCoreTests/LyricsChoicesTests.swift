import Foundation
import Testing
@testable import ColCore

struct LyricsChoicesTests {
    private let track = LyricsQuery(title: "Midnight City (Remastered)", artist: "M83 feat. Someone", album: "Hurry Up", duration: 243)

    @Test func theOffsetMovesByHalfSecondsWithinHalfAMinute() {
        var overrides = LyricsOverrides()
        overrides.nudge(track, by: 1)
        overrides.nudge(track, by: 1)
        #expect(overrides.offset(for: track) == 1)
        overrides.nudge(track, by: -3)
        #expect(overrides.offset(for: track) == -0.5)
        overrides.nudge(track, by: 500)
        #expect(overrides.offset(for: track) == LyricsOverrides.limit)
        overrides.resetOffset(track)
        #expect(overrides.offset(for: track) == 0)
        // Nothing left to remember: the track is forgotten.
        #expect(overrides.tracks.isEmpty)
    }

    @Test func settingsFollowTheTrackWhateverThePlayerCallsIt() {
        var overrides = LyricsOverrides()
        overrides.setHidden(true, for: track)
        let same = LyricsQuery(title: "Midnight City", artist: "M83", album: "", duration: 243.4)
        #expect(overrides.isHidden(same))
        #expect(!overrides.isHidden(LyricsQuery(title: "Midnight City", artist: "M83", album: "", duration: 300)))
        #expect(overrides.settings(for: same)?.title == "Midnight City")
        #expect(overrides.settings(for: same)?.artist == "M83")
    }

    @Test func hiddenTracksAreListedNewestFirstAndCanComeBack() {
        var overrides = LyricsOverrides()
        let other = LyricsQuery(title: "Other", artist: "Band", album: "", duration: 100)
        overrides.setHidden(true, for: track, now: Date(timeIntervalSince1970: 10))
        overrides.setHidden(true, for: other, now: Date(timeIntervalSince1970: 20))
        overrides.nudge(other, by: 1, now: Date(timeIntervalSince1970: 21))
        #expect(overrides.hiddenTracks.map(\.settings.title) == ["Other", "Midnight City"])
        overrides.unhide(key: track.cacheKey)
        #expect(overrides.hiddenTracks.map(\.settings.title) == ["Other"])
        // Shown again, its timing stays.
        overrides.unhide(key: other.cacheKey)
        #expect(overrides.hiddenTracks.isEmpty)
        #expect(overrides.offset(for: other) == 0.5)
    }

    @Test func aNewChoiceStartsOnTime() {
        var overrides = LyricsOverrides()
        overrides.nudge(track, by: 2)
        overrides.choose(42, for: track)
        #expect(overrides.choice(for: track) == 42)
        #expect(overrides.offset(for: track) == 0)
        overrides.nudge(track, by: -1)
        overrides.choose(42, for: track)
        #expect(overrides.offset(for: track) == -0.5)
        overrides.choose(nil, for: track)
        #expect(overrides.choice(for: track) == nil)
    }

    @Test func theOldestAreForgottenFirst() {
        var overrides = LyricsOverrides()
        for index in 0...LyricsOverrides.capacity {
            let query = LyricsQuery(title: "Song \(index)", artist: "A", album: "", duration: 100)
            overrides.setHidden(true, for: query, now: Date(timeIntervalSince1970: Double(index)))
        }
        #expect(overrides.tracks.count == LyricsOverrides.capacity)
        #expect(!overrides.isHidden(LyricsQuery(title: "Song 0", artist: "A", album: "", duration: 100)))
        #expect(overrides.isHidden(LyricsQuery(title: "Song 1", artist: "A", album: "", duration: 100)))
    }

    @Test func overridesSurviveASaveAndARead() throws {
        var overrides = LyricsOverrides()
        overrides.nudge(track, by: -2)
        overrides.choose(7, for: track)
        overrides.nudge(track, by: 1)
        let read = try JSONDecoder().decode(LyricsOverrides.self, from: JSONEncoder().encode(overrides))
        #expect(read == overrides)
        #expect(read.offset(for: track) == 0.5)
    }

    @Test func searchResultsRankTheLikelyOnesFirst() throws {
        let json = """
        [
          {"id": 1, "trackName": "Midnight City", "artistName": "M83", "duration": 300, "syncedLyrics": "[00:01.00]x"},
          {"id": 2, "trackName": "Midnight City", "artistName": "M83", "duration": 244, "plainLyrics": "x"},
          {"id": 3, "trackName": "Midnight City", "artistName": "M83", "duration": 243, "syncedLyrics": "[00:01.00]x"},
          {"id": 4, "trackName": "Midnight City", "artistName": "M83", "duration": 243},
          {"id": 3, "trackName": "Duplicate", "artistName": "M83", "duration": 243, "syncedLyrics": "[00:01.00]x"},
          {"id": 5, "trackName": "Midnight City", "artistName": "M83", "duration": 250, "syncedLyrics": "[00:01.00]x"},
          {"trackName": null, "artistName": "M83", "id": 6, "duration": 243, "instrumental": true}
        ]
        """
        let records = try JSONDecoder().decode([LyricsRecord].self, from: Data(json.utf8))
        let ranked = LyricsRecord.ranked(records, for: track)
        // Same length with synced lyrics, then plain, then instrumental; then the others, closest length first.
        #expect(ranked.map(\.id) == [3, 2, 6, 5, 1])
        #expect(ranked.first?.lyrics?.isSynced == true)
        #expect(LyricsRecord.ranked(records, for: track, limit: 2).count == 2)
    }

    @Test func aRecordGivesItsBestLyrics() {
        let synced = LyricsRecord(id: 1, trackName: "a", artistName: "b", plainLyrics: "plain", syncedLyrics: "[00:01.00]timed")
        #expect(synced.lyrics?.isSynced == true)
        let plain = LyricsRecord(id: 1, trackName: "a", artistName: "b", plainLyrics: "plain", syncedLyrics: "")
        #expect(plain.lyrics?.isSynced == false)
        #expect(LyricsRecord(id: 1, trackName: "a", artistName: "b").lyrics == nil)
    }
}

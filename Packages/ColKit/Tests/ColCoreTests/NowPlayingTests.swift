import Foundation
import Testing
@testable import ColCore

struct NowPlayingTests {
    func update(_ json: String) throws -> NowPlayingUpdate {
        try NowPlayingUpdate(from: Data(json.utf8))
    }

    @Test func readsABridgeLine() throws {
        let line = try update(#"{"album":"A","artist":"B","duration":60,"elapsed":10,"pid":42,"playing":1,"rate":1,"timestamp":1000,"title":"T","artwork":"AAEC"}"#)
        var state = NowPlaying()
        #expect(state.apply(line) == .replaced(Data([0, 1, 2])))
        #expect(state.title == "T" && state.artist == "B" && state.album == "A")
        #expect(state.isPlaying && state.pid == 42 && state.duration == 60)
    }

    @Test func extrapolatesThePositionWhilePlaying() throws {
        var state = NowPlaying()
        _ = state.apply(try update(#"{"title":"T","duration":60,"elapsed":10,"playing":1,"rate":1,"timestamp":1000}"#))
        #expect(state.position(at: Date(timeIntervalSince1970: 1005)) == 15)
        #expect(state.position(at: Date(timeIntervalSince1970: 2000)) == 60)
    }

    @Test func freezesThePositionWhilePaused() throws {
        var state = NowPlaying()
        _ = state.apply(try update(#"{"title":"T","duration":60,"elapsed":10,"playing":0,"rate":0,"timestamp":1000}"#))
        #expect(state.position(at: Date(timeIntervalSince1970: 1030)) == 10)
    }

    @Test func artworkSemantics() throws {
        var state = NowPlaying()
        #expect(state.apply(try update(#"{"title":"T","playing":1}"#)) == .unchanged)
        #expect(state.apply(try update(#"{"title":"T","playing":1,"artwork":""}"#)) == .removed)
        #expect(state.apply(try update(#"{"title":"T","artwork":"not base64!"}"#)) == .unchanged)
    }

    @Test func idleClearsEverything() throws {
        var state = NowPlaying()
        _ = state.apply(try update(#"{"title":"T","artist":"A","pid":3,"playing":1}"#))
        #expect(!state.isEmpty)
        #expect(state.apply(try update(#"{"idle":true}"#)) == .removed)
        #expect(state.isEmpty && !state.isPlaying)
    }

    @Test func acceptsTrueBooleansToo() throws {
        var state = NowPlaying()
        _ = state.apply(try update(#"{"title":"T","playing":true}"#))
        #expect(state.isPlaying)
    }
}

struct NowPlayingCommandTests {
    @Test func pausingKeepsThePosition() throws {
        var state = NowPlaying()
        _ = state.apply(try NowPlayingUpdate(from: Data(#"{"title":"T","duration":60,"elapsed":10,"playing":1,"rate":1,"timestamp":1000}"#.utf8)))
        state.setPlaying(false, at: Date(timeIntervalSince1970: 1004))
        #expect(state.position(at: Date(timeIntervalSince1970: 1100)) == 14)
        state.setPlaying(true, at: Date(timeIntervalSince1970: 1100))
        #expect(state.position(at: Date(timeIntervalSince1970: 1102)) == 16)
    }

    @Test func seekingIsClamped() throws {
        var state = NowPlaying()
        _ = state.apply(try NowPlayingUpdate(from: Data(#"{"title":"T","duration":60,"playing":0,"timestamp":1000}"#.utf8)))
        state.seek(to: 99, at: Date(timeIntervalSince1970: 1000))
        #expect(state.position(at: Date(timeIntervalSince1970: 1000)) == 60)
        state.seek(to: -3, at: Date(timeIntervalSince1970: 1000))
        #expect(state.position(at: Date(timeIntervalSince1970: 1000)) == 0)
    }
}

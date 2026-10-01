import Foundation
import Testing
@testable import IsletCore

struct ActivityBoardTests {
    let now = Date(timeIntervalSince1970: 1_000)

    func activity(_ id: String, _ priority: ActivityPriority, at offset: TimeInterval = 0, expires: TimeInterval? = nil) -> Activity {
        Activity(
            id: id,
            priority: priority,
            compact: CompactPresentation(leading: .symbol("circle")),
            expires: expires.map { now.addingTimeInterval($0) },
            updated: now.addingTimeInterval(offset)
        )
    }

    @Test func higherPriorityWins() {
        var board = ActivityBoard()
        board.upsert(activity("music", .ambient, at: 5))
        board.upsert(activity("volume", .transient, at: 1, expires: 2))
        #expect(board.current(now: now)?.id == "volume")
    }

    @Test func amongEqualsTheLatestWins() {
        var board = ActivityBoard()
        board.upsert(activity("build", .standard, at: 1))
        board.upsert(activity("timer", .standard, at: 2))
        #expect(board.current(now: now)?.id == "timer")
    }

    @Test func expiredActivitiesStepAside() {
        var board = ActivityBoard()
        board.upsert(activity("music", .ambient))
        board.upsert(activity("volume", .transient, expires: 1.5))
        let later = now.addingTimeInterval(2)
        #expect(board.current(now: later)?.id == "music")
        let first = board.prune(now: later)
        let second = board.prune(now: later)
        #expect(first)
        #expect(board.activities["volume"] == nil)
        #expect(second == false)
    }

    @Test func wakesAtTheNextExpiry() {
        var board = ActivityBoard()
        board.upsert(activity("a", .transient, expires: 3))
        board.upsert(activity("b", .transient, expires: 1))
        board.upsert(activity("c", .ambient))
        #expect(board.nextExpiry(after: now) == now.addingTimeInterval(1))
    }

    @Test func emptyBoardShowsNothing() {
        var board = ActivityBoard()
        #expect(board.current(now: now) == nil)
        board.upsert(activity("x", .standard))
        board.remove("x")
        #expect(board.current(now: now) == nil)
    }

    @Test func theUsersOrderDecidesAmongWhatRuns() {
        var board = ActivityBoard()
        board.upsert(activity("media", .ambient, at: 1))
        board.upsert(activity("agents", .standard, at: 2))
        #expect(board.current(now: now)?.id == "agents")
        board.ranking = [.music]
        #expect(board.ranking.first == .music)
        #expect(board.ranking.count == ActivitySource.allCases.count)
        #expect(board.current(now: now)?.id == "media")
    }

    @Test func alertsComeFirstWhateverTheOrder() {
        var board = ActivityBoard()
        board.ranking = [.music]
        board.upsert(activity("media", .ambient))
        board.upsert(activity("agents", .alert))
        #expect(board.current(now: now)?.id == "agents")
    }

    @Test func sourcesAreReadFromIdentifiers() {
        #expect(ActivitySource(activityID: "download.report.pdf") == .downloads)
        #expect(ActivitySource(activityID: "api.ext-weather") == .scripts)
        #expect(ActivitySource(activityID: "media.track") == .music)
        #expect(ActivitySource(activityID: "hud") == nil)
    }

    @Test func tiesResolveTheSameWayEveryTime() {
        var board = ActivityBoard()
        board.upsert(activity("b", .standard))
        board.upsert(activity("a", .standard))
        #expect(board.current(now: now)?.id == "a")
    }
}

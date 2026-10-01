import CoreGraphics
import Foundation
import Testing
@testable import ColCore

struct PaceTests {
    @Test func readingTimeFollowsThePace() {
        #expect(Pace.readingTime(words: 300, wordsPerMinute: 150) == 120)
        #expect(Pace.readingTime(words: 0, wordsPerMinute: 150) == 0)
        #expect(Pace.readingTime(words: 10, wordsPerMinute: 0) == 0)
    }

    @Test func rollingCoversTheWholeScriptInItsReadingTime() {
        // 160 words at 150 a minute: 64 s, the last line's 10 words read once it reaches the camera, so the other 150
        // take the 600 points of scrolling in 60 s, paragraph spacing and all.
        #expect(Pace.pointsPerSecond(toScroll: 600, words: 160, wordsOnLastLine: 10, wordsPerMinute: 150) == 10)
        #expect(Pace.pointsPerSecond(toScroll: 600, words: 0, wordsOnLastLine: 0, wordsPerMinute: 150) == 0)
        #expect(Pace.pointsPerSecond(toScroll: 0, words: 50, wordsOnLastLine: 5, wordsPerMinute: 150) == 0)
    }

    @Test func aScriptFitsAChosenDuration() {
        // 150 words in one minute: 150 words a minute; 120 in 45 seconds: 160.
        #expect(Pace.wordsPerMinute(toRead: 150, in: 60) == 150)
        #expect(Pace.wordsPerMinute(toRead: 120, in: 45) == 160)
        #expect(Pace.wordsPerMinute(toRead: 0, in: 60) == 0)
        #expect(Pace.wordsPerMinute(toRead: 10, in: 0) == 0)
    }

    @Test func offersOnlyTheDurationsTheSpeedsCanReach() {
        // 120 words, between 60 and 260 words a minute: from about 28 seconds to two minutes.
        #expect(Pace.fittingDurations(words: 120, range: 60...260) == [30, 45, 60, 90, 120])
        #expect(Pace.fittingDurations(words: 0, range: 60...260).isEmpty)
    }

    @Test func clockShowsMinutesAndSeconds() {
        #expect(Pace.clock(0) == "0:00")
        #expect(Pace.clock(65) == "1:05")
        #expect(Pace.clock(3_725) == "1:02:05")
        #expect(Pace.clock(-3) == "0:00")
    }

    @Test func meterMeasuresTheRecentPace() {
        var meter = PaceMeter(span: 10)
        let start = Date(timeIntervalSince1970: 0)
        meter.record(wordIndex: 0, at: start)
        meter.record(wordIndex: 25, at: start.addingTimeInterval(10))
        #expect(meter.wordsPerMinute == 150)
    }

    @Test func meterForgetsOldSamples() {
        var meter = PaceMeter(span: 10)
        let start = Date(timeIntervalSince1970: 0)
        meter.record(wordIndex: 0, at: start)
        meter.record(wordIndex: 100, at: start.addingTimeInterval(5))
        meter.record(wordIndex: 110, at: start.addingTimeInterval(25))
        meter.record(wordIndex: 120, at: start.addingTimeInterval(29))
        #expect(meter.wordsPerMinute == 150)
    }

    @Test func meterIsQuietWithoutEnoughTime() {
        var meter = PaceMeter(span: 10)
        meter.record(wordIndex: 3, at: Date(timeIntervalSince1970: 0))
        #expect(meter.wordsPerMinute == nil)
    }

    @Test func autoScrollSpeedTurnsPaceIntoPoints() {
        // 120 words a minute, 10 words a line, 30 points a line: 12 lines a minute, 6 points a second.
        #expect(Pace.pointsPerSecond(wordsPerMinute: 120, wordsPerLine: 10, lineHeight: 30) == 6)
    }
}

struct TakeSummaryTests {
    @Test func summarisesATake() {
        let start = Date(timeIntervalSince1970: 0)
        var recorder = TakeRecorder(totalWords: 200, start: start)
        recorder.record(wordIndex: 50, at: start.addingTimeInterval(20))
        recorder.record(wordIndex: 60, at: start.addingTimeInterval(32))
        recorder.record(wordIndex: 150, at: start.addingTimeInterval(60))
        recorder.heard("so um we uh launch")
        let summary = recorder.finish(at: start.addingTimeInterval(60))
        #expect(summary.duration == 60)
        #expect(summary.wordsRead == 150)
        #expect(summary.averageWordsPerMinute == 150)
        #expect(summary.coverage == 0.75)
        #expect(summary.longestPause == 28)
        #expect(summary.fillers == 2)
    }

    @Test func suggestsTheReadersOwnPaceAfterAFullTake() {
        let take = TakeSummary(duration: 60, wordsRead: 146, totalWords: 200, longestPause: 2, fillers: 0)
        #expect(take.suggestedPace(range: 60...260) == 145)
        // Too short a take to trust.
        #expect(TakeSummary(duration: 8, wordsRead: 20, totalWords: 200, longestPause: 0, fillers: 0).suggestedPace(range: 60...260) == nil)
        // Within the speeds the slider offers.
        #expect(TakeSummary(duration: 60, wordsRead: 300, totalWords: 400, longestPause: 0, fillers: 0).suggestedPace(range: 60...260) == 260)
    }

    @Test func anEmptyTakeHasNoPace() {
        let start = Date(timeIntervalSince1970: 0)
        let summary = TakeRecorder(totalWords: 0, start: start).finish(at: start)
        #expect(summary.averageWordsPerMinute == 0)
        #expect(summary.coverage == 0)
    }
}

struct NotchGeometryTests {
    @Test func readsTheHardwareNotch() {
        let notch = NotchMetrics.resolve(screenWidth: 1512, safeAreaTop: 32, leftAreaWidth: 662, rightAreaWidth: 662, menuBarHeight: 37)
        #expect(notch == NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true))
    }

    @Test func drawsItsOwnNotchWithoutHardware() {
        let notch = NotchMetrics.resolve(screenWidth: 2560, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil, menuBarHeight: 25)
        #expect(notch == NotchMetrics(width: 180, height: 25, centerX: 1280, isHardware: false))
    }

    @Test func thePrompterGrowsOutOfTheNotch() {
        let notch = NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true)
        let layout = PrompterLayout(notch: notch, width: 520, textHeight: 150)
        // Closed, it is the camera housing itself; open, it drops from the top of the screen around it.
        let closed = layout.shape(open: false)
        #expect(closed.width == 188 && closed.height == 32)
        let open = layout.shape(open: true)
        #expect(open.width == 520 && open.height == 32 + 150)
        #expect(layout.bodyFrame.minY == 0)
        // The text starts right under the camera.
        #expect(layout.textFrame.minY == 32 && layout.textFrame.height == 150)
        #expect(layout.textFrame.width == 520)
    }

    @Test func theTimeAndTheVoiceSitEitherSideOfTheCamera() {
        let notch = NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true)
        let layout = PrompterLayout(notch: notch, width: 520, textHeight: 150)
        let wings = layout.wingFrames
        #expect(wings.left.minX == layout.bodyFrame.minX && wings.right.maxX == layout.bodyFrame.maxX)
        #expect(wings.left.minY == 0 && wings.left.height == 32 && wings.right.height == 32)
        // Nothing is drawn under the camera: the wings stop at its edges.
        #expect(wings.right.minX - wings.left.maxX == 188)
        #expect(abs(wings.left.maxX - (layout.canvasSize.width / 2 - 94)) < 0.01)
    }

    @Test func thePrompterLeavesRoomBesideTheCamera() {
        let notch = NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true)
        let layout = PrompterLayout(notch: notch, width: 200, textHeight: 100)
        // Enough for the time on one side ("● 0:06 −0:51") and the voice on the other, with room to spare.
        #expect(layout.shape(open: true).width >= 188 + 190)
        #expect(layout.wingFrames.left.width >= 95 && layout.wingFrames.right.width >= 95)
    }

    @Test func theOpenPrompterKeepsTheClassicProportions() {
        let notch = NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true)
        let open = PrompterLayout(notch: notch, width: 400, textHeight: 136).shape(open: true)
        // Ears of 25 points and lower corners of 13 on a prompter 400 points wide, in proportion at any width.
        #expect(abs(open.earRadius - 25) < 0.01)
        #expect(abs(open.cornerRadius - 13) < 0.01)
        let wide = PrompterLayout(notch: notch, width: 480, textHeight: 136).shape(open: true)
        #expect(abs(wide.earRadius - 30) < 0.01)
    }

    @Test func withoutANotchThePrompterStillDropsFromTheTopOfTheScreen() {
        let notch = NotchMetrics(width: 180, height: 25, centerX: 1280, isHardware: false)
        let layout = PrompterLayout(notch: notch, width: 520, textHeight: 150)
        // The menu bar's height makes the camera row; the text starts below it.
        #expect(layout.bodyFrame.minY == 0)
        #expect(layout.shape(open: true).height == CGFloat(25 + 150))
        #expect(layout.shape(open: true).earRadius > 0)
        #expect(layout.textFrame.minY == 25)
        // Closed, a sliver at the top edge, as wide as the space kept for the camera.
        #expect(layout.shape(open: false).width == 180 && layout.shape(open: false).height < 10)
    }

    @Test func theOutlineIsClosedCentredAndHangsFromItsTopEdge() {
        let shape = PrompterShape(width: 200, height: 100, earRadius: 10, cornerRadius: 20)
        let box = PrompterPath.make(shape, centerX: 300).boundingBoxOfPath
        #expect(abs(box.midX - 300) < 0.5)
        #expect(abs(box.width - 220) < 0.5)
        #expect(abs(box.height - 100) < 0.5)
        #expect(abs(box.minY) < 0.5)
    }
}

struct RemoteProtocolTests {
    @Test func parsesARequestLineWithItsQuery() throws {
        let raw = "GET /command?token=abc123&action=faster HTTP/1.1\r\nHost: 192.168.1.4:7575\r\nAccept: */*\r\n\r\n"
        let request = try #require(HTTPRequest(Data(raw.utf8)))
        #expect(request.method == "GET")
        #expect(request.path == "/command")
        #expect(request.query["token"] == "abc123")
        #expect(request.query["action"] == "faster")
        #expect(request.headers["host"] == "192.168.1.4:7575")
    }

    @Test func rejectsAnIncompleteRequest() {
        #expect(HTTPRequest(Data("GET /command HTTP/1.1\r\nHost: x".utf8)) == nil)
        #expect(HTTPRequest(Data("nonsense\r\n\r\n".utf8)) == nil)
    }

    @Test func commandsHaveStableNames() {
        #expect(RemoteCommand(rawValue: "toggle") == .toggle)
        #expect(RemoteCommand.allCases.map(\.rawValue) == ["toggle", "faster", "slower", "back", "forward", "restart"])
    }

    @Test func stateEncodesToJSON() throws {
        let state = RemoteState(title: "Keynote", isRolling: true, progress: 0.5, wordsPerMinute: 140, line: "Hello there", remaining: 42)
        let json = try #require(String(data: JSONEncoder().encode(state), encoding: .utf8))
        #expect(json.contains("\"title\":\"Keynote\""))
        #expect(try JSONDecoder().decode(RemoteState.self, from: Data(json.utf8)) == state)
    }

    @Test func anIdleStateTellsThePhoneNothingIsOpen() throws {
        let idle = RemoteState.idle(title: "Keynote")
        #expect(!idle.isActive && !idle.isRolling && idle.line.isEmpty && idle.title == "Keynote")
        let json = try #require(String(data: JSONEncoder().encode(idle), encoding: .utf8))
        #expect(json.contains("\"isActive\":false"))
        // An open take is active even while the line under the camera is blank.
        #expect(RemoteState(title: "Keynote", isRolling: false, progress: 0, wordsPerMinute: 140, line: "", remaining: 30).isActive)
    }

    @Test func tokensAreLongAndUnguessable() {
        let token = RemoteToken.make()
        #expect(token.count == 12)
        #expect(token != RemoteToken.make())
        #expect(RemoteToken.matches(token, token))
        #expect(!RemoteToken.matches(token, "nope"))
    }
}

import Foundation
import Testing
@testable import ColCore

struct ClipboardHistoryTests {
    let now = Date(timeIntervalSince1970: 0)

    @Test func newestFirstWithoutRepeats() {
        var history = ClipboardHistory()
        history.add("a", at: now)
        history.add("b", at: now)
        history.add("a", at: now)
        #expect(history.entries.map(\.text) == ["a", "b"])
    }

    @Test func ignoresBlanksAndKeepsTheCapacity() {
        var history = ClipboardHistory(capacity: 3)
        history.add("   \n", at: now)
        for text in ["1", "2", "3", "4"] { history.add(text, at: now) }
        #expect(history.entries.map(\.text) == ["4", "3", "2"])
    }

    @Test func removesAndClears() {
        var history = ClipboardHistory()
        history.add("x", at: now)
        history.add("y", at: now)
        history.remove(history.entries[0].id)
        #expect(history.entries.map(\.text) == ["x"])
        history.clear()
        #expect(history.entries.isEmpty)
    }

    @Test func pinsStayOnTopAndSurviveTheCapacity() {
        var history = ClipboardHistory(capacity: 2)
        history.add("keep", at: now)
        history.togglePin(history.entries[0].id)
        for text in ["a", "b", "c"] { history.add(text, at: now) }
        #expect(history.ordered.map(\.text) == ["keep", "c", "b"])
        history.clear()
        #expect(history.ordered.map(\.text) == ["keep"])
        #expect(history.pinnedTexts == ["keep"])
    }

    @Test func recopyingAPinKeepsItPinned() {
        var history = ClipboardHistory()
        history.add("x", at: now)
        history.togglePin(history.entries[0].id)
        history.add("x", at: now)
        #expect(history.entries.count == 1)
        #expect(history.entries[0].pinned)
    }

    @Test func keepsImages() {
        var history = ClipboardHistory()
        let png = Data([1, 2, 3])
        history.add(image: png, label: "Image 10 × 10", at: now)
        history.add(image: png, label: "Image 10 × 10", at: now)
        #expect(history.entries.count == 1)
        #expect(history.entries[0].isImage)
    }

    @Test func restoresPins() {
        var history = ClipboardHistory()
        history.restorePinned(["one", "two"])
        #expect(history.ordered.map(\.text) == ["one", "two"])
        history.restorePinned(["one"])
        #expect(history.entries.count == 2)
    }
}

struct CountdownTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func countsDownWithoutTicking() {
        let timer = Countdown(total: 300, starting: start)
        #expect(timer.remaining(at: start.addingTimeInterval(60)) == 240)
        #expect(timer.fraction(at: start.addingTimeInterval(150)) == 0.5)
        #expect(timer.isFinished(at: start.addingTimeInterval(301)))
    }

    @Test func pausesAndResumes() {
        var timer = Countdown(total: 100, starting: start)
        timer.pause(at: start.addingTimeInterval(30))
        #expect(timer.remaining(at: start.addingTimeInterval(500)) == 70)
        #expect(!timer.isFinished(at: start.addingTimeInterval(500)))
        timer.resume(at: start.addingTimeInterval(500))
        #expect(timer.remaining(at: start.addingTimeInterval(510)) == 60)
    }

    @Test func formats() {
        #expect(Countdown.format(245) == "4:05")
        #expect(Countdown.format(0.2) == "0:01")
        #expect(Countdown.format(0) == "0:00")
        #expect(Countdown.format(3723) == "1:02:03")
    }
}

struct MeetingLinkTests {
    @Test func findsAVideoCall() {
        let url = MeetingLink.find(in: [nil, "Salle 3", "Rejoindre : https://meet.google.com/abc-defg-hij merci"])
        #expect(url?.host == "meet.google.com")
        #expect(MeetingLink.find(in: ["https://us02web.zoom.us/j/123"])?.host == "us02web.zoom.us")
    }

    @Test func ignoresOrdinaryLinks() {
        #expect(MeetingLink.find(in: ["https://example.com/agenda"]) == nil)
        #expect(MeetingLink.find(in: []) == nil)
    }
}

@Suite struct ClipboardPollingTests {
    @Test func spacesOutWhileTheMacSitsIdle() {
        #expect(ClipboardPolling.interval(secondsSinceInput: 1) == 2)
        #expect(ClipboardPolling.interval(secondsSinceInput: 60) == 8)
        #expect(ClipboardPolling.interval(secondsSinceInput: 600) == 30)
    }
}

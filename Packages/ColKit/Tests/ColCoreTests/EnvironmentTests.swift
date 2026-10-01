import CoreGraphics
import Testing
@testable import ColCore

struct FullScreenTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func aWindowCoveringTheScreenIsFullScreen() {
        let windows = [FullScreen.Window(layer: 0, bounds: screen, ownerPID: 42)]
        #expect(FullScreen.isActive(windows: windows, screen: screen, frontmostPID: 42))
    }

    @Test func aMaximisedWindowLeavesTheMenuBar() {
        let windows = [FullScreen.Window(layer: 0, bounds: CGRect(x: 0, y: 37, width: 1512, height: 945), ownerPID: 42)]
        #expect(!FullScreen.isActive(windows: windows, screen: screen, frontmostPID: 42))
    }

    @Test func onlyTheFrontmostAppCounts() {
        let windows = [FullScreen.Window(layer: 0, bounds: screen, ownerPID: 7)]
        #expect(!FullScreen.isActive(windows: windows, screen: screen, frontmostPID: 42))
        #expect(!FullScreen.isActive(windows: windows, screen: screen, frontmostPID: nil))
    }

    @Test func overlaysDoNotCount() {
        let windows = [FullScreen.Window(layer: 25, bounds: screen, ownerPID: 42)]
        #expect(!FullScreen.isActive(windows: windows, screen: screen, frontmostPID: 42))
    }
}

struct DownloadTrackerTests {
    @Test func followsADownload() {
        var tracker = DownloadTracker()
        #expect(tracker.update(listing: ["a.txt"]) == [])
        #expect(tracker.update(listing: ["a.txt", "Report.pdf.download"]) == [.started("Report.pdf")])
        #expect(tracker.update(listing: ["a.txt", "Report.pdf.download"]) == [])
        #expect(tracker.update(listing: ["a.txt", "Report.pdf"]) == [.finished("Report.pdf")])
    }

    @Test func noticesACancelledDownload() {
        var tracker = DownloadTracker()
        _ = tracker.update(listing: ["movie.mp4.crdownload"])
        #expect(tracker.update(listing: []) == [.cancelled("movie.mp4")])
    }

    @Test func knowsPartialNames() {
        #expect(DownloadTracker.finalName(of: "x.zip.part") == "x.zip")
        #expect(DownloadTracker.finalName(of: "x.zip") == nil)
    }
}

struct AccessoryBatteryTests {
    @Test func zeroMeansUnknown() {
        #expect(AccessoryBattery.level(0) == nil)
        #expect(AccessoryBattery.level(85) == 85)
        #expect(AccessoryBattery.level(140) == nil)
    }

    @Test func summarisesTheLowestEarbud() {
        #expect(AccessoryBattery(left: 80, right: 65, caseLevel: 40).summary == 65)
        #expect(AccessoryBattery(single: 55).summary == 55)
        #expect(AccessoryBattery().isEmpty)
    }
}

struct WingBudgetTests {
    @Test func measuresFreeSpaceOnEachSide() {
        #expect(WingBudget.free(notchEdge: 662, nearestItem: 600, leftSide: true) == CGFloat(54))
        #expect(WingBudget.free(notchEdge: 850, nearestItem: 1000, leftSide: false) == CGFloat(142))
        #expect(WingBudget.free(notchEdge: 662, nearestItem: 700, leftSide: true) == CGFloat(0))
        #expect(WingBudget.free(notchEdge: 662, nearestItem: nil, leftSide: true) == nil)
    }

    @Test func capsTheWingsToTheTighterSide() {
        #expect(WingBudget.allowed(requested: 80, left: 54, right: 140) == Wings(54))
        #expect(WingBudget.allowed(requested: 40, left: 54, right: 140) == Wings(40))
        #expect(WingBudget.allowed(requested: 80, left: nil, right: nil) == Wings(80))
    }

    @Test func keepsOneWingWhenAMenuFillsTheOtherSide() {
        // A long menu reaches the notch: the right side still shows the activity.
        #expect(WingBudget.allowed(requested: 60, left: 12, right: 140) == Wings(leading: 0, trailing: 60))
        #expect(WingBudget.allowed(requested: 60, left: 140, right: 0) == Wings(leading: 60, trailing: 0))
    }

    @Test func givesUpWhenNotEvenAnIconFits() {
        #expect(WingBudget.allowed(requested: 60, left: 12, right: 20) == Wings.none)
        #expect(WingBudget.allowed(requested: 0, left: 12, right: 140) == Wings.none)
    }
}

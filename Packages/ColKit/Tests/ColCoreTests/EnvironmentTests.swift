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

    @Test func leavesRoomForTheEarsAndTheSwell() {
        // macOS 27's chevron for hidden menu bar items, 26.5 points from a 14-inch MacBook Pro's notch: 18.5 points
        // of room once the margin is kept, too little for an icon once the ears and the swell are counted.
        let room = WingBudget.free(notchEdge: 848.5, nearestItem: 875, leftSide: false)
        #expect(room == CGFloat(18.5))
        #expect(WingBudget.allowed(requested: 40, left: 200, right: room, overhang: 10) == Wings(leading: 40, trailing: 0))
        // With room enough, the wing stops where the overhang still clears the item.
        #expect(WingBudget.allowed(requested: 80, left: 60, right: 200, overhang: 10) == Wings(50))
    }
}

@Suite struct ActivityPlacementTests {
    let strip = Wings.beneath(leading: 15, trailing: 40)

    @Test func besideTheCameraWhenTheMenuBarLeavesRoom() {
        #expect(WingBudget.placement(leading: 32, trailing: 32, beneath: strip, left: 120, right: 90, canHangBeneath: true) == Wings(32))
        // One side only still keeps a wing there.
        #expect(WingBudget.placement(leading: 32, trailing: 32, beneath: strip, left: 120, right: 10, canHangBeneath: true) == Wings(leading: 32, trailing: 0))
    }

    @Test func beneathWhenThereIsNoRoomOrNoWayToSee() {
        // Menus against the notch on both sides, as with a browser whose menus run past the notch.
        #expect(WingBudget.placement(leading: 32, trailing: 32, beneath: strip, left: 2.5, right: 1.5, canHangBeneath: true) == strip)
        // Without Accessibility the menu bar cannot be read: beneath, never over what Col cannot see.
        #expect(WingBudget.placement(leading: 32, trailing: 32, beneath: strip, left: nil, right: nil, readable: false, canHangBeneath: true) == strip)
        // Asked for in Settings.
        #expect(WingBudget.placement(leading: 32, trailing: 32, beneath: strip, left: 200, right: 200, canHangBeneath: true, prefersBeneath: true) == strip)
    }

    @Test func aSideThatCouldNotBeMeasuredDoesNotLimitItsWing() {
        #expect(WingBudget.placement(leading: 32, trailing: 32, beneath: strip, left: nil, right: 90, canHangBeneath: true) == Wings(32))
    }

    @Test func aPillKeepsANarrowWingWhenItCannotSee() {
        let wings = WingBudget.placement(leading: 80, trailing: 80, beneath: strip, left: nil, right: nil, readable: false, canHangBeneath: false)
        #expect(wings == Wings(WingBudget.unknownRoom))
        #expect(WingBudget.placement(leading: 80, trailing: 80, beneath: strip, left: 10, right: 10, canHangBeneath: false).isEmpty)
    }

    @Test func nothingToShowShowsNothing() {
        #expect(WingBudget.placement(leading: 0, trailing: 0, beneath: strip, left: nil, right: nil, readable: false, canHangBeneath: true) == .none)
    }

    @Test func eachWingIsAsWideAsItsOwnItem() {
        // An icon beside a line of text: the icon's wing stays narrow.
        #expect(WingBudget.allowed(leading: 32, trailing: 100, left: 200, right: 200) == Wings(leading: 32, trailing: 100))
        // The text side shrinks to its room, the icon keeps its own.
        #expect(WingBudget.allowed(leading: 32, trailing: 100, left: 200, right: 60) == Wings(leading: 32, trailing: 60))
        // A single item takes a single wing.
        #expect(WingBudget.allowed(leading: 0, trailing: 32, left: 200, right: 200) == Wings(leading: 0, trailing: 32))
        // Its own side blocked, it moves to the other.
        #expect(WingBudget.allowed(leading: 0, trailing: 32, left: 200, right: 5) == Wings(leading: 32, trailing: 0))
        // One item cannot have its side: a single wing shows the value, at the value's width.
        #expect(WingBudget.allowed(leading: 100, trailing: 32, left: 50, right: 5) == Wings(leading: 32, trailing: 0))
        #expect(WingBudget.allowed(leading: 32, trailing: 54, left: 200, right: 10) == Wings(leading: 54, trailing: 0))
        #expect(WingBudget.allowed(leading: 32, trailing: 32, left: 5, right: 5).isEmpty)
    }

    @Test func smallItemsKeepTheirWingOnASmallMenuBar() {
        // A 24-point menu bar: an icon asks for 28 points, under the minimum, and still gets its wing.
        #expect(WingBudget.allowed(leading: 28, trailing: 28, left: 200, right: 200) == Wings(28))
        #expect(WingBudget.allowed(requested: 28, left: 200, right: 200) == Wings(28))
        // A short count beside an icon keeps its own short wing.
        #expect(WingBudget.allowed(leading: 32, trailing: 23, left: 200, right: 200) == Wings(leading: 32, trailing: 23))
        // But a wing squeezed below what it holds is no wing.
        #expect(WingBudget.allowed(leading: 28, trailing: 28, left: 20, right: 20).isEmpty)
    }
}

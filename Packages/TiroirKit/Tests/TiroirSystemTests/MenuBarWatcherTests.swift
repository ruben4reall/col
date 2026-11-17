import CoreGraphics
import Testing
@testable import TiroirSystem

@Suite struct MenuBarWatcherTests {
    /// A 1512 by 982 display whose menu bar is 37 points high, as on a 14-inch MacBook Pro.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let barBottom: CGFloat = 945
    let icons = [CGRect(x: 1400, y: 945, width: 30, height: 37), CGRect(x: 1360, y: 945, width: 30, height: 37)]

    @Test func emptyRoomBetweenTheMenusAndTheIconsCounts() {
        #expect(MenuBarWatcher.isEmptySpot(CGPoint(x: 1000, y: 960), screen: screen, barBottom: barBottom, menusEnd: 420, occupied: icons))
    }

    @Test func theAppMenusKeepTheirClicks() {
        #expect(!MenuBarWatcher.isEmptySpot(CGPoint(x: 300, y: 960), screen: screen, barBottom: barBottom, menusEnd: 420, occupied: icons))
        #expect(!MenuBarWatcher.isEmptySpot(CGPoint(x: 425, y: 960), screen: screen, barBottom: barBottom, menusEnd: 420, occupied: icons),
                "a little room after the last menu stays the menu's")
    }

    @Test func iconsKeepTheirClicks() {
        #expect(!MenuBarWatcher.isEmptySpot(CGPoint(x: 1410, y: 960), screen: screen, barBottom: barBottom, menusEnd: 420, occupied: icons))
        #expect(!MenuBarWatcher.isEmptySpot(CGPoint(x: 1357, y: 960), screen: screen, barBottom: barBottom, menusEnd: 420, occupied: icons),
                "the edge of an icon counts as the icon")
    }

    @Test func belowTheMenuBarIsNotTheMenuBar() {
        #expect(!MenuBarWatcher.isEmptySpot(CGPoint(x: 1000, y: 900), screen: screen, barBottom: barBottom, menusEnd: 420, occupied: icons))
        #expect(!MenuBarWatcher.isEmptySpot(CGPoint(x: 2000, y: 960), screen: screen, barBottom: barBottom, menusEnd: 420, occupied: icons))
    }

    @Test func withoutMeasuredMenusOnlyTheRightHalfCounts() {
        #expect(!MenuBarWatcher.isEmptySpot(CGPoint(x: 700, y: 960), screen: screen, barBottom: barBottom, menusEnd: nil, occupied: icons))
        #expect(MenuBarWatcher.isEmptySpot(CGPoint(x: 900, y: 960), screen: screen, barBottom: barBottom, menusEnd: nil, occupied: icons))
    }
}

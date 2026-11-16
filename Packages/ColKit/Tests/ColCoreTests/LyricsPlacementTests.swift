import Foundation
import Testing
@testable import ColCore

struct LyricsPlacementTests {
    /// The screens of the MacBooks with a notch, in points: 14-inch, 16-inch, 13-inch Air (and 15-inch's default).
    static let screens: [CGSize] = [CGSize(width: 1512, height: 982), CGSize(width: 1728, height: 1117), CGSize(width: 1470, height: 956)]

    @Test(arguments: screens)
    func theCardStaysBetweenTheClockAndThePasswordField(size: CGSize) {
        let screen = CGRect(origin: .zero, size: size)
        let card = LockScreenLayout.card(screen: screen)
        let clockBottom = screen.maxY - screen.height * LockScreenLayout.clockShare
        let userTop = screen.minY + screen.height * LockScreenLayout.userShare
        #expect(card.maxY <= clockBottom)
        #expect(card.minY >= userTop)
        // Room for the lines and the controls, never wider than reads well.
        #expect(card.height >= 300)
        #expect(card.width >= 480 && card.width <= 720)
        #expect(abs(card.midX - screen.midX) <= 1)
    }

    @Test func theCardFollowsAScreenThatIsNotAtTheOrigin() {
        let screen = CGRect(x: 1512, y: -200, width: 1728, height: 1117)
        let card = LockScreenLayout.card(screen: screen)
        #expect(screen.contains(card))
        #expect(abs(card.midX - screen.midX) <= 1)
    }

    @Test func aSmallScreenStillGetsACardInsideIt() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 300)
        let card = LockScreenLayout.card(screen: screen)
        #expect(screen.contains(card))
        #expect(card.width <= 400)
    }

    @Test func desktopLyricsStayOnTheScreenWhereverTheyAre() {
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 875)
        for position in DesktopLyricsPosition.allCases {
            for size in DesktopLyricsSize.allCases {
                let frame = DesktopLyricsLayout.frame(position: position, size: size, visible: visible)
                #expect(visible.contains(frame), "\(position) \(size)")
                #expect(frame.height >= size.lineSize * 2)
            }
        }
        let left = DesktopLyricsLayout.frame(position: .lowerLeft, size: .medium, visible: visible)
        let right = DesktopLyricsLayout.frame(position: .lowerRight, size: .medium, visible: visible)
        let center = DesktopLyricsLayout.frame(position: .center, size: .medium, visible: visible)
        #expect(left.maxX < visible.midX && right.minX > visible.midX)
        #expect(left.minY == right.minY && left.minY < center.minY)
        #expect(abs(center.midY - visible.midY) <= 1)
    }
}

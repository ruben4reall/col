import CoreGraphics
import Foundation
import Testing
@testable import TiroirCore

@Suite struct TintGeometryTests {
    /// A display without a notch, the main one: 1920 by 1080, a menu bar 24 points tall.
    let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    /// A MacBook's display with its notch: 1512 by 982, a menu bar as tall as the notch, 188 points of camera housing.
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let laptopLeft = CGRect(x: 0, y: 950, width: 662, height: 32)
    let laptopRight = CGRect(x: 850, y: 950, width: 662, height: 32)

    @Test func theFullWidthCoversTheMenuBar() {
        let pieces = TintGeometry.pieces(for: .full, screen: display, menuBarHeight: 24)
        #expect(pieces == TintGeometry.Pieces(rects: [CGRect(x: 0, y: 1056, width: 1920, height: 24)], radius: 0, shape: .full))
    }

    @Test func aFloatingBarIsInsetAndRound() {
        let pieces = TintGeometry.pieces(for: .floating, screen: display, menuBarHeight: 24)
        #expect(pieces.rects == [CGRect(x: 6, y: 1059, width: 1908, height: 18)])
        #expect(pieces.radius == 9)
        #expect(pieces.shape == .floating)
    }

    @Test func splitFollowsTheMenusAndTheIcons() {
        let pieces = TintGeometry.pieces(for: .split, screen: display, menuBarHeight: 24, menusEnd: 412, statusStart: 1480)
        #expect(pieces.rects == [CGRect(x: 6, y: 1059, width: 412, height: 18), CGRect(x: 1474, y: 1059, width: 440, height: 18)])
        #expect(pieces.radius == 9)
        #expect(pieces.shape == .split)
    }

    @Test func splitEndsAtTheNotch() {
        let pieces = TintGeometry.pieces(for: .split, screen: laptop, menuBarHeight: 32, notchLeft: laptopLeft, notchRight: laptopRight)
        #expect(pieces.rects == [CGRect(x: 6, y: 953, width: 650, height: 26), CGRect(x: 856, y: 953, width: 650, height: 26)])
        #expect(pieces.radius == 13)
        #expect(pieces.shape == .split)
    }

    /// Beside a notch the measures do not count: the notch is where the menus stop and the icons begin.
    @Test func theNotchWinsOverTheMeasures() {
        let measured = TintGeometry.pieces(for: .split, screen: laptop, menuBarHeight: 32, notchLeft: laptopLeft,
                                           notchRight: laptopRight, menusEnd: 300, statusStart: 1300)
        #expect(measured == TintGeometry.pieces(for: .split, screen: laptop, menuBarHeight: 32, notchLeft: laptopLeft, notchRight: laptopRight))
    }

    /// Only the widths of the areas beside the notch count, so either coordinate space gives the same pieces.
    @Test func theNotchAreasCountByTheirWidths() {
        let elsewhere = TintGeometry.pieces(for: .split, screen: laptop, menuBarHeight: 32,
                                            notchLeft: CGRect(x: 0, y: 0, width: 662, height: 32),
                                            notchRight: CGRect(x: 0, y: 0, width: 662, height: 32))
        #expect(elsewhere == TintGeometry.pieces(for: .split, screen: laptop, menuBarHeight: 32, notchLeft: laptopLeft, notchRight: laptopRight))
    }

    @Test func aMissingMeasureFloatsRatherThanGuesses() {
        let floating = TintGeometry.pieces(for: .floating, screen: display, menuBarHeight: 24)
        #expect(TintGeometry.pieces(for: .split, screen: display, menuBarHeight: 24, statusStart: 1480) == floating)
        #expect(TintGeometry.pieces(for: .split, screen: display, menuBarHeight: 24, menusEnd: 412) == floating)
        #expect(TintGeometry.pieces(for: .split, screen: display, menuBarHeight: 24) == floating)
        // Half a notch is no notch.
        #expect(TintGeometry.pieces(for: .split, screen: laptop, menuBarHeight: 32, notchLeft: laptopLeft).shape == .floating)
    }

    /// Menus that reach the icons leave no desktop between the pieces: one bar reads better than two touching.
    @Test func menusThatReachTheIconsFloat() {
        #expect(TintGeometry.pieces(for: .split, screen: display, menuBarHeight: 24, menusEnd: 1470, statusStart: 1480).shape == .floating)
        #expect(TintGeometry.pieces(for: .split, screen: display, menuBarHeight: 24, menusEnd: 1600, statusStart: 1480).shape == .floating)
        // An app with barely any menu would leave a dot on the left.
        #expect(TintGeometry.pieces(for: .split, screen: display, menuBarHeight: 24, menusEnd: 8, statusStart: 1480).shape == .floating)
    }

    @Test func eachDisplayHasItsOwnPieces() {
        // A second display on the left of the laptop, their tops aligned.
        let left = CGRect(x: -1920, y: -98, width: 1920, height: 1080)
        let pieces = TintGeometry.pieces(for: .split, screen: left, menuBarHeight: 24, menusEnd: -1508, statusStart: -440)
        #expect(pieces.rects == [CGRect(x: -1914, y: 961, width: 412, height: 18), CGRect(x: -446, y: 961, width: 440, height: 18)])
        #expect(TintGeometry.pieces(for: .floating, screen: left, menuBarHeight: 24).rects == [CGRect(x: -1914, y: 961, width: 1908, height: 18)])
        // Measures taken on another display never land on this one.
        #expect(TintGeometry.pieces(for: .split, screen: left, menuBarHeight: 24, menusEnd: 412, statusStart: 1480).shape == .floating)
        #expect(TintGeometry.pieces(for: .split, screen: left, menuBarHeight: 24, menusEnd: 412, statusStart: -440).shape == .floating)
        #expect(TintGeometry.pieces(for: .split, screen: left, menuBarHeight: 24, menusEnd: -1508, statusStart: 1480).shape == .floating)
    }

    @Test func aVeryNarrowScreenIsTintedEdgeToEdge() {
        let narrow = CGRect(x: 0, y: 0, width: 20, height: 400)
        let edgeToEdge = TintGeometry.Pieces(rects: [CGRect(x: 0, y: 376, width: 20, height: 24)], radius: 0, shape: .full)
        #expect(TintGeometry.pieces(for: .floating, screen: narrow, menuBarHeight: 24) == edgeToEdge)
        #expect(TintGeometry.pieces(for: .split, screen: narrow, menuBarHeight: 24, menusEnd: 8, statusStart: 12) == edgeToEdge)
        // Wide enough to float, too narrow to split.
        let small = CGRect(x: 0, y: 0, width: 120, height: 400)
        #expect(TintGeometry.pieces(for: .split, screen: small, menuBarHeight: 24, menusEnd: 50, statusStart: 70).shape == .floating)
    }

    @Test func aThinOrHiddenMenuBar() {
        #expect(TintGeometry.pieces(for: .floating, screen: display, menuBarHeight: 5).shape == .full)
        #expect(TintGeometry.pieces(for: .split, screen: display, menuBarHeight: 0).rects.isEmpty)
        #expect(TintGeometry.pieces(for: .full, screen: display, menuBarHeight: -3).rects.isEmpty)
    }

    @Test func piecesStayOnTheirScreen() {
        let measures: [(CGFloat, CGFloat)] = [(412, 1480), (-50, 1480), (412, 2400), (1900, 30), (960, 961)]
        for shape in Appearance.Shape.allCases {
            for (menusEnd, statusStart) in measures {
                let pieces = TintGeometry.pieces(for: shape, screen: display, menuBarHeight: 24, menusEnd: menusEnd, statusStart: statusStart)
                for rect in pieces.rects {
                    #expect(display.contains(rect), "\(shape) \(menusEnd) \(statusStart): \(rect)")
                    #expect(rect.width >= rect.height)
                }
            }
        }
    }

    @Test func menusAndIconsAreMeasuredPerMenuBar() {
        let laptopBar = CGRect(x: 0, y: 950, width: 1512, height: 32)
        let leftBar = CGRect(x: -1920, y: 958, width: 1920, height: 24)
        let menus = [CGRect(x: 10, y: 950, width: 34, height: 32), CGRect(x: 44, y: 950, width: 70, height: 32),
                     CGRect(x: -1910, y: 958, width: 34, height: 24), CGRect(x: -1876, y: 958, width: 90, height: 24)]
        #expect(TintGeometry.menusEnd(of: menus, in: laptopBar) == 114)
        #expect(TintGeometry.menusEnd(of: menus, in: leftBar) == -1786)
        #expect(TintGeometry.menusEnd(of: [], in: laptopBar) == nil)
        // An icon pushed past the screen's left edge counts on no menu bar.
        let icons = [CGRect(x: 1363, y: 950, width: 151, height: 32), CGRect(x: 1209, y: 950, width: 42, height: 32),
                     CGRect(x: -3000, y: 950, width: 30, height: 32)]
        #expect(TintGeometry.statusStart(of: icons, in: laptopBar) == 1209)
        #expect(TintGeometry.statusStart(of: icons, in: leftBar) == nil)
    }
}

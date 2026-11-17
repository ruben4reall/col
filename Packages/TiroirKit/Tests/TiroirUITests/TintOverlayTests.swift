import AppKit
import QuartzCore
import Testing
import TiroirCore
@testable import TiroirUI

@MainActor
@Suite struct TintOverlayTests {
    let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    let menuBar = CGRect(x: 0, y: 576, width: 800, height: 24)

    /// Nothing new runs at rest: without a dark look the system's appearance is not watched, and without anything to
    /// draw, not even with one.
    @Test func darkModeIsWatchedOnlyForADarkLookThatShows() {
        #expect(!TintOverlay.watchesSystemAppearance(for: .standard))
        #expect(!TintOverlay.watchesSystemAppearance(for: Appearance(tint: .color, shape: .split)))
        #expect(!TintOverlay.watchesSystemAppearance(for: Appearance(darkLook: Appearance.Look())))
        #expect(TintOverlay.watchesSystemAppearance(for: Appearance(tint: .color, darkLook: Appearance.Look())))
        #expect(TintOverlay.watchesSystemAppearance(for: Appearance(darkLook: Appearance.Look(tint: .gradient))))
    }

    /// Beside a notch the split pieces end at the notch: the front app's menus matter only on a display without one.
    @Test func theFrontAppIsWatchedOnlyForSplitWithoutANotch() {
        #expect(TintOverlay.watchesFrontApp(for: .split, screensWithoutNotch: 1))
        #expect(!TintOverlay.watchesFrontApp(for: .split, screensWithoutNotch: 0))
        #expect(!TintOverlay.watchesFrontApp(for: .floating, screensWithoutNotch: 2))
        #expect(!TintOverlay.watchesFrontApp(for: .full, screensWithoutNotch: 2))
    }

    /// The full width draws as it always has: the tint over the bar, a hairline along its bottom, a shade below.
    @Test func theFullWidthDrawsAsBefore() throws {
        let look = Appearance.Look(tint: .color, border: true, shadow: true)
        let pieces = TintGeometry.pieces(for: .full, screen: screen, menuBarHeight: 24)
        let frame = TintLayers.windowFrame(menuBar: menuBar, look: look)
        #expect(frame == CGRect(x: 0, y: 564, width: 800, height: 36))
        let layer = CALayer()
        TintLayers.draw(look, in: pieces, frame: frame, scale: 2, on: layer)
        let sublayers = try #require(layer.sublayers)
        #expect(sublayers.map(\.frame) == [
            CGRect(x: 0, y: 12, width: 800, height: 24), CGRect(x: 0, y: 12, width: 800, height: 0.5), CGRect(x: 0, y: 0, width: 800, height: 12),
        ])
        #expect(sublayers[2] is CAGradientLayer)
    }

    /// Rounded pieces cast their shadow around them only: under a translucent tint it would show as a stain.
    @Test func roundedPiecesCastTheirShadowOutside() throws {
        let look = Appearance.Look(tint: .gradient, border: true, shadow: true)
        let pieces = TintGeometry.pieces(for: .floating, screen: screen, menuBarHeight: 24)
        let layer = CALayer()
        TintLayers.draw(look, in: pieces, frame: TintLayers.windowFrame(menuBar: menuBar, look: look), scale: 2, on: layer)
        let sublayers = try #require(layer.sublayers)
        #expect(sublayers.count == 3)
        #expect(sublayers[0].shadowPath != nil)
        #expect((sublayers[0].mask as? CAShapeLayer)?.fillRule == .evenOdd)
        #expect(sublayers[1] is CAGradientLayer)
        #expect(sublayers[1].mask is CAShapeLayer)
        #expect((sublayers[2] as? CAShapeLayer)?.strokeColor != nil)
    }

    @Test func aLookWithoutTintDrawsOnlyWhatItAsks() throws {
        let look = Appearance.Look(border: true)
        let layer = CALayer()
        TintLayers.draw(look, in: TintGeometry.pieces(for: .split, screen: screen, menuBarHeight: 24, menusEnd: 200, statusStart: 600),
                        frame: TintLayers.windowFrame(menuBar: menuBar, look: look), scale: 2, on: layer)
        let sublayers = try #require(layer.sublayers)
        #expect(sublayers.count == 1)
        #expect(sublayers[0] is CAShapeLayer)
    }

    @Test func everyShapeHasItsOwnName() {
        let names = Appearance.Shape.allCases.map(Strings.shapeName)
        #expect(Set(names).count == names.count)
        #expect(!names.contains(""))
    }
}

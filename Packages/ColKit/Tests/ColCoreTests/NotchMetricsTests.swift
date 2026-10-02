import CoreGraphics
import Testing
@testable import ColCore

struct NotchMetricsTests {
    @Test func readsTheHardwareNotch() {
        // 14-inch MacBook Pro at its default scaled resolution.
        let notch = NotchMetrics.resolve(
            screenWidth: 1512, safeAreaTop: 32, leftAreaWidth: 662, rightAreaWidth: 662, menuBarHeight: 37
        )
        #expect(notch == NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true))
    }

    @Test func followsAnOffCentreNotch() {
        let notch = NotchMetrics.resolve(
            screenWidth: 1000, safeAreaTop: 30, leftAreaWidth: 400, rightAreaWidth: 400, menuBarHeight: 30
        )
        #expect(notch.centerX == 500)
        let shifted = NotchMetrics.resolve(
            screenWidth: 1000, safeAreaTop: 30, leftAreaWidth: 300, rightAreaWidth: 500, menuBarHeight: 30
        )
        #expect(shifted.centerX == 400)
    }

    @Test func drawsItsOwnNotchWithoutHardware() {
        let notch = NotchMetrics.resolve(
            screenWidth: 2560, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil, menuBarHeight: 25
        )
        #expect(notch == NotchMetrics(width: 180, height: 25, centerX: 1280, isHardware: false))
    }

    @Test func survivesAHiddenMenuBar() {
        let notch = NotchMetrics.resolve(
            screenWidth: 1920, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil, menuBarHeight: 0
        )
        #expect(notch.height == 24)
    }

    @Test func ignoresInconsistentAreas() {
        let notch = NotchMetrics.resolve(
            screenWidth: 1000, safeAreaTop: 32, leftAreaWidth: 600, rightAreaWidth: 600, menuBarHeight: 32
        )
        #expect(notch.isHardware == false)
    }
}

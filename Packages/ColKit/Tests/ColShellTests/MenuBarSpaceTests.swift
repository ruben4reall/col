import CoreGraphics
@testable import ColShell
import Testing

/// The wings' room on macOS 27.2, from MenuBarAgent's slots as read on a 14-inch MacBook Pro (notch from 663 to 849).
@Suite struct MenuBarSpaceTests {
    static let bar = CGRect(x: 0, y: 0, width: 1512, height: 33)

    static func slot(_ x: CGFloat, _ width: CGFloat, overflow: Bool = false) -> MenuBarSpace.AgentBar.Slot {
        MenuBarSpace.AgentBar.Slot(frame: CGRect(x: x, y: 0, width: width, height: 33), isOverflow: overflow)
    }

    static func bars(_ frame: CGRect, _ slots: [MenuBarSpace.AgentBar.Slot]) -> [MenuBarSpace.AgentBar] {
        [MenuBarSpace.AgentBar(frame: frame, slots: slots)]
    }

    /// With the drawers on, Col's own icon and the input menu sit left of Apple's items: they count.
    @Test func everyDrawnIconCounts() {
        let items = [Self.slot(1332, 26), Self.slot(1374, 118), Self.slot(1164, 22), Self.slot(1122, 26), Self.slot(1084, 22),
                     Self.slot(1194, 32), Self.slot(1260, 32), Self.slot(1226, 34), Self.slot(1032, 44), Self.slot(1292, 32),
                     Self.slot(998, 34)]
        #expect(MenuBarSpace.drawnLeftEdge(of: Self.bars(Self.bar, items), after: 849, top: 0, span: 0...1512) == 998)
    }

    /// Icons that do not fit wait stacked left of the » button, undrawn: the button is the edge.
    @Test func iconsBehindTheOverflowButtonDoNotCount() {
        let items = [Self.slot(974, 38), Self.slot(974, 38), Self.slot(977, 35), Self.slot(995, 18, overflow: true),
                     Self.slot(1020, 38), Self.slot(1374, 118)]
        #expect(MenuBarSpace.drawnLeftEdge(of: Self.bars(Self.bar, items), after: 849, top: 0, span: 0...1512) == 995)
    }

    @Test func anotherDisplaysBarDoesNotCount() {
        let other = CGRect(x: 1512, y: -400, width: 1920, height: 25)
        let items = [Self.slot(1600, 30)]
        #expect(MenuBarSpace.drawnLeftEdge(of: Self.bars(other, items), after: 849, top: 0, span: 0...1512) == nil)
    }

    /// Seen while MenuBarAgent lays the bar out, with no » button: an icon let through sits stacked on Col's own. Neither
    /// counts; the next drawn icon is the edge, not a stacked one right beside the notch.
    @Test func stackedIconsWithoutTheOverflowButtonDoNotCount() {
        let items = [Self.slot(870, 34), Self.slot(872, 32), Self.slot(1032, 44), Self.slot(1084, 22), Self.slot(1374, 118)]
        #expect(MenuBarSpace.drawnLeftEdge(of: Self.bars(Self.bar, items), after: 849, top: 0, span: 0...1512) == 1032)
    }
}

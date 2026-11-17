import AppKit
import Carbon.HIToolbox
import Testing
import TiroirCore
@testable import TiroirSystem

/// What changed when the drawers moved into Col's process, and what macOS 27.2 showed on a real menu bar.
@MainActor
@Suite struct AgentDiscoveryTests {
    static func item(_ bundleID: String?, x: CGFloat, pid: pid_t, identifier: String? = nil, overflow: Bool = false) -> AgentLayout.Item {
        AgentLayout.Item(bundleID: bundleID, systemIdentifier: nil, frame: CGRect(x: x, y: 0, width: 32, height: 33), pid: pid,
                         element: nil, isOverflowButton: overflow, label: nil, identifier: identifier)
    }

    static func found(_ bundleID: String, pid: pid_t) -> FoundIcon {
        FoundIcon(app: RunningApp(pid: pid, bundleID: bundleID, name: bundleID), frame: CGRect(x: 900, y: 0, width: 30, height: 33))
    }

    /// On macOS 27.2 most apps no longer describe their icons: MenuBarAgent's slots name them instead.
    @Test func appsThatDoNotDescribeTheirIconsComeFromMenuBarAgent() {
        let bar = AgentLayout.Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), items: [
            Self.item("com.google.drivefs", x: 1058, pid: 10),
            Self.item("ch.rubencatalao.pli", x: 974, pid: 11),
            Self.item("ch.rubencatalao.piste", x: 977, pid: 12, identifier: "principale"),
            Self.item(nil, x: 995, pid: 1, overflow: true),
        ])
        let found = GoldenGateEngine.adding(AgentLayout(displays: [bar], agentPID: 1), to: [Self.found("com.google.drivefs", pid: 10)],
                                            ownPID: 99)
        #expect(found.map(\.app.bundleID).sorted() == ["ch.rubencatalao.piste", "ch.rubencatalao.pli", "com.google.drivefs"])
        #expect(found.first { $0.app.bundleID == "ch.rubencatalao.piste" }?.identifier == "principale")
    }

    /// Col's own drawers are drawn by MenuBarAgent too: they are never icons to sort.
    @Test func colsOwnItemsAreLeftOut() {
        let bar = AgentLayout.Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), items: [
            Self.item("ch.rubencatalao.islet", x: 1200, pid: 99),
            Self.item("ch.rubencatalao.islet", x: 1230, pid: 99),
            Self.item("dev.kdrag0n.MacVirt", x: 1100, pid: 20),
        ])
        let found = GoldenGateEngine.adding(AgentLayout(displays: [bar], agentPID: 1), to: [], ownPID: 99)
        #expect(found.map(\.app.bundleID) == ["dev.kdrag0n.MacVirt"])
    }

    /// Each display has a bar with every app: an app's icons are counted once.
    @Test func anAppOnTwoDisplaysCountsOnce() {
        let first = AgentLayout.Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), items: [Self.item("a.b.c", x: 1000, pid: 5)])
        let second = AgentLayout.Display(frame: CGRect(x: 1512, y: 0, width: 1920, height: 25), items: [Self.item("a.b.c", x: 3000, pid: 5)])
        let found = GoldenGateEngine.adding(AgentLayout(displays: [first, second], agentPID: 1), to: [], ownPID: 99)
        #expect(found.count == 1)
        #expect(found.first?.frame.minX == 1000)
    }

    /// macOS 27.2 keeps three windows over one display: the one with the apps' live buttons is the bar on screen.
    @Test func ofWindowsOverOneDisplayTheLiveOneWins() {
        let bar = CGRect(x: 0, y: 0, width: 1512, height: 33)
        #expect(AgentReader.chooseBars([(bar, 3), (bar, 15), (bar, 0)]) == [1])
        #expect(AgentReader.chooseBars([(bar, 15), (bar, 15)]) == [0])
        let other = CGRect(x: 1512, y: 0, width: 1920, height: 25)
        #expect(AgentReader.chooseBars([(bar, 15), (other, 9), (nil, 4), (bar, 2)]) == [0, 1])
    }
}

/// Col has a shortcut of its own on the same event target: a press that is not one of the drawers' goes on to it.
@MainActor
@Suite struct SharedShortcutTests {
    @Test func aPressOfColsShortcutIsNotTheDrawers() {
        let registrar = CarbonHotKeyRegistrar()
        #expect(!registrar.pressed(EventHotKeyID(signature: OSType(0x49534C54), id: 1)))
        #expect(!registrar.pressed(EventHotKeyID(signature: CarbonHotKeyRegistrar.signature, id: 42)))
    }
}

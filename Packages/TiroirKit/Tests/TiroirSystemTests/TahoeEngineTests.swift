import AppKit
import Testing
import TiroirCore
@testable import TiroirSystem

@MainActor
@Suite struct TahoeEngineTests {
    let bar: SimulatedBar
    let icons: SimulatedIcons
    let divider: SimulatedDivider
    let engine: TahoeEngine

    init() {
        bar = SimulatedBar(apps: [
            ("com.google.drivefs", 32), ("com.protonmail.bridge", 38), ("com.anthropic.claudefordesktop", 40), ("ch.rubencatalao.pli", 38),
        ])
        icons = SimulatedIcons(bar: bar)
        let divider = SimulatedDivider(bar: bar)
        self.divider = divider
        engine = TahoeEngine(icons: icons, windows: bar, poster: bar, activity: IdlePerson(), makeDivider: { divider },
                             isOnScreen: { $0.maxX > 0 && $0.minX < SimulatedBar.screenWidth }, isSafeDrop: { _ in true }, pause: instant)
    }

    /// A plan as LayoutPlanner makes it: every other icon of the bar is visible.
    func plan(hiding bundleIDs: Set<String>) -> VisibilityPlan {
        let concealed = Set(bundleIDs.map { IconID(bundleID: $0) })
        let everyone = Set(bar.entries.filter { $0.windowID != SimulatedBar.dividerWindow }.map { IconID(bundleID: $0.bundleID, key: $0.key) })
        return VisibilityPlan(visible: everyone.subtracting(concealed), concealed: concealed, hiddenApps: bundleIDs)
    }

    @Test func scanNamesEveryIconAndSkipsTheDivider() async {
        await engine.start()
        let snapshot = await engine.scan()
        #expect(snapshot.icons.count == 6)
        #expect(!snapshot.bundleIDs.contains("ch.rubencatalao.tiroir"))
        #expect(snapshot.icon(IconID(bundleID: "com.google.drivefs"))?.windowID == 100)
        #expect(snapshot.icon(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock"))?.isMovable == false)
        #expect(snapshot.icon(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock"))?.kind == .system)
    }

    @Test func applyCarriesMisplacedIconsLeftOfTheDividerAndHidesThem() async {
        await engine.start()
        #expect(bar.order == ["|", "ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "com.protonmail.bridge", "com.google.drivefs"])
        let report = await engine.apply(plan(hiding: ["com.google.drivefs", "com.protonmail.bridge"]))
        #expect(Set(report.moved) == [IconID(bundleID: "com.google.drivefs"), IconID(bundleID: "com.protonmail.bridge")])
        #expect(report.failed.isEmpty)
        let divider = bar.order.firstIndex(of: "|")!
        #expect(bar.order.firstIndex(of: "com.google.drivefs")! < divider)
        #expect(bar.order.firstIndex(of: "com.protonmail.bridge")! < divider)
        #expect(bar.order.firstIndex(of: "com.anthropic.claudefordesktop")! > divider)
        #expect(self.divider.isExpanded)
    }

    /// Seen on a real menu bar: two neighbours hidden together came back swapped once Tiroir quit.
    @Test func iconsHiddenTogetherKeepTheirOrder() async {
        await engine.start()
        let before = bar.order.filter { $0 != "|" }
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop"]))
        #expect(bar.order == ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "|", "com.protonmail.bridge", "com.google.drivefs"])
        // Quitting takes the divider away: every icon shows, in the order it had.
        divider.remove()
        #expect(bar.order == before)
    }

    @Test func anIconOpenedFromADrawerGoesBackToItsOwnPlace() async throws {
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tiroir", key: "drawer", width: 30, pid: 1), at: 2)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop"]))
        let hidden = bar.order
        let bar = self.bar
        icons.onPress = { _ in bar.openMenuOwners = [2003] }
        try await engine.open(IconID(bundleID: "ch.rubencatalao.pli"), anchor: bar.frame(50)!)
        bar.openMenuOwners = []
        let deadline = ContinuousClock.now + .seconds(3)
        while bar.order != hidden, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(bar.order == hidden, "back next to the divider, not at the far left of the hidden icons")
    }

    /// Seen on a real menu bar: Claude has a second icon macOS keeps out of the menu bar, parked at x -1. Once Tiroir
    /// hid the real one far left, the parked one became the rightmost and took its identity.
    @Test func anIconMacOSKeepsOutNeverShiftsTheOthers() async {
        icons.windowless = [FoundIcon(app: RunningApp(pid: 2002, bundleID: "com.anthropic.claudefordesktop", name: "Claude"),
                                      frame: CGRect(x: -1, y: 0, width: 42, height: 33))]
        await engine.start()
        #expect(await engine.scan().icon(IconID(bundleID: "com.anthropic.claudefordesktop")) != nil, "one icon: no rank in its name")
        _ = await engine.apply(plan(hiding: ["com.anthropic.claudefordesktop"]))
        let drags = bar.drags.count
        let again = await engine.apply(plan(hiding: ["com.anthropic.claudefordesktop"]))
        #expect(again.moved.isEmpty && again.failed.isEmpty)
        #expect(bar.drags.count == drags, "hidden once, left alone after")
    }

    @Test func twoIconsOfOneAppKeepTheirNamesWhenOneHides() async {
        bar.entries.insert(SimulatedBar.Entry(windowID: 120, bundleID: "com.google.drivefs", width: 30, pid: 2000), at: 3)
        await engine.start()
        let before = await engine.scan()
        let right = try? #require(before.icons.first { $0.id.bundleID == "com.google.drivefs" })
        let rightID = right?.id
        #expect(rightID == IconID(bundleID: "com.google.drivefs", key: "#0"))
        let plan = VisibilityPlan(visible: Set(before.icons.map(\.id)).subtracting([rightID!]), concealed: [rightID!], hiddenApps: [])
        _ = await engine.apply(plan)
        let after = await engine.scan()
        #expect(after.icon(rightID!)?.windowID == right?.windowID, "the hidden icon is still #0")
        let drags = bar.drags.count
        _ = await engine.apply(plan)
        #expect(bar.drags.count == drags)
    }

    /// Seen on a real menu bar: Pli, busy right after its move, missed the Accessibility timeout; its icon dropped out
    /// of the scan, nothing was left to hide, and the divider let it come back.
    @Test func anAppThatDoesNotAnswerKeepsItsIconsHidden() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli"]))
        #expect(divider.isExpanded)
        icons.silent = ["ch.rubencatalao.pli"]
        let snapshot = await engine.scan()
        #expect(snapshot.icon(IconID(bundleID: "ch.rubencatalao.pli")) != nil, "known from its window")
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli"]))
        #expect(divider.isExpanded)
    }

    @Test func anIconWhoseWindowIsGoneIsGone() async {
        await engine.start()
        _ = await engine.scan()
        icons.silent = ["ch.rubencatalao.pli"]
        bar.entries.removeAll { $0.bundleID == "ch.rubencatalao.pli" }
        #expect(await engine.scan().icon(IconID(bundleID: "ch.rubencatalao.pli")) == nil)
    }

    @Test func showingEveryIconMovesNothing() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs", "com.protonmail.bridge"]))
        let drags = bar.drags.count
        let report = await engine.apply(.showEverything)
        #expect(report.moved.isEmpty)
        #expect(bar.drags.count == drags)
        #expect(!divider.isExpanded)
        // Back to the layout: still no move, the divider just widens again.
        _ = await engine.apply(plan(hiding: ["com.google.drivefs", "com.protonmail.bridge"]))
        #expect(bar.drags.count == drags)
        #expect(divider.isExpanded)
    }

    @Test func iconsAlreadyInPlaceAreNotMovedAgain() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        let dragsBefore = bar.drags.count
        let report = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.moved.isEmpty)
        #expect(bar.drags.count == dragsBefore)
        #expect(divider.isExpanded)
    }

    @Test func showingAnIconAgainCarriesItBack() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs", "ch.rubencatalao.pli"]))
        let report = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.moved == [IconID(bundleID: "ch.rubencatalao.pli")])
        #expect(bar.order.firstIndex(of: "ch.rubencatalao.pli")! > bar.order.firstIndex(of: "|")!)
    }

    @Test func nothingToHideRelaxesTheDivider() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        _ = await engine.apply(plan(hiding: []))
        #expect(!divider.isExpanded)
    }

    @Test func aMoveThatNeverLandsIsReportedNotRepeatedForever() async {
        await engine.start()
        bar.ignoresDrags = true
        let report = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.failed == [IconID(bundleID: "com.google.drivefs")])
        #expect(bar.drags.count == 6, "every posting route and drop variant, then it gives up")
    }

    @Test func restoreRelaxesTheDivider() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        engine.restore()
        #expect(divider.removed)
        #expect(!divider.isExpanded)
    }

    @Test func permissionLossShowsEverything() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        icons.isTrusted = false
        let snapshot = await engine.scan()
        #expect(snapshot.icons.isEmpty)
        #expect(engine.status == .needsAccessibility)
        #expect(!divider.isExpanded)
    }

    @Test func aVisibleIconIsPressedWhereItIs() async throws {
        await engine.start()
        try await engine.open(IconID(bundleID: "com.anthropic.claudefordesktop"), anchor: nil)
        #expect(icons.pressed == ["com.anthropic.claudefordesktop"])
        #expect(bar.drags.isEmpty)
    }

    @Test func anIconThatRefusesThePressIsClicked() async throws {
        await engine.start()
        icons.refusesPress = ["com.anthropic.claudefordesktop"]
        try await engine.open(IconID(bundleID: "com.anthropic.claudefordesktop"), anchor: nil)
        #expect(bar.clicks == [102])
    }

    @Test func aConcealedIconComesNextToItsDrawerThenGoesBack() async throws {
        // Tiroir's drawer item: a status item right of the other icons.
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tiroir", key: "drawer", width: 30, pid: 1), at: 2)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(bar.order.firstIndex(of: "com.google.drivefs")! < bar.order.firstIndex(of: "|")!)
        let anchor = bar.frame(50)!
        let bar = self.bar
        icons.onPress = { _ in bar.openMenuOwners = [2000] }
        try await engine.open(IconID(bundleID: "com.google.drivefs"), anchor: anchor)
        #expect(icons.pressed == ["com.google.drivefs"])
        func nextToItsDrawer() -> Bool {
            let drive = bar.frame(100)!, drawer = bar.frame(50)!
            return drive.maxX <= drawer.minX + 1 && drive.maxX >= drawer.minX - 1
        }
        #expect(nextToItsDrawer(), "the icon sits right next to its drawer, on screen, while its menu is open")
        // An arrangement meanwhile leaves it there.
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        try await Task.sleep(for: .milliseconds(60))
        #expect(nextToItsDrawer(), "still there while its menu is open")
        // The menu closes: the icon goes back behind the divider, which widens again.
        bar.openMenuOwners = []
        let deadline = ContinuousClock.now + .seconds(5)
        while !(bar.order.firstIndex(of: "com.google.drivefs")! < bar.order.firstIndex(of: "|")! && divider.isExpanded),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(bar.order.firstIndex(of: "com.google.drivefs")! < bar.order.firstIndex(of: "|")!)
        #expect(divider.isExpanded)
    }

    /// Seen on a real, crowded menu bar: with an icon shown next to its drawer, the divider sat beside the notch, no
    /// drop landed next to it, and the icon stayed in the menu bar. It goes back through an arrangement that first takes
    /// the divider away from the notch.
    @Test func anIconGoesBackEvenWhenTheDividerSitsBesideTheNotch() async throws {
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tiroir", key: "drawer", width: 30, pid: 1), at: 2)
        let divider = self.divider
        let engine = TahoeEngine(icons: icons, windows: bar, poster: bar, activity: IdlePerson(), makeDivider: { divider },
                                 isOnScreen: { $0.maxX > 0 && $0.minX < SimulatedBar.screenWidth }, isSafeDrop: { $0 >= 1225 },
                                 pause: instant)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop"]))
        #expect(bar.order == ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "|", "com.protonmail.bridge", "com.google.drivefs",
                              "ch.rubencatalao.tiroir"])
        let bar = self.bar
        icons.onPress = { _ in bar.openMenuOwners = [2003] }
        try await engine.open(IconID(bundleID: "ch.rubencatalao.pli"), anchor: bar.frame(50)!)
        #expect(bar.order.firstIndex(of: "ch.rubencatalao.pli")! > bar.order.firstIndex(of: "|")!, "shown next to its drawer")
        bar.openMenuOwners = []
        // Done once the divider is wide again: the icon goes behind it first, the icons that show come back after.
        let deadline = ContinuousClock.now + .seconds(5)
        while !(bar.order.firstIndex(of: "ch.rubencatalao.pli")! < bar.order.firstIndex(of: "|")! && divider.isExpanded),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let order = bar.order
        let divided = order.firstIndex(of: "|")!
        #expect(order.firstIndex(of: "ch.rubencatalao.pli")! < divided, "back behind the divider")
        #expect(order.firstIndex(of: "com.anthropic.claudefordesktop")! < divided)
        #expect(order.suffix(from: divided + 1) == ["com.protonmail.bridge", "com.google.drivefs", "ch.rubencatalao.tiroir"],
                "the icons that show keep their order")
        #expect(divider.isExpanded)
    }

    /// The engine of `anIconGoesBack…` tests, with drops refused left of `safeFrom`, like beside a notch.
    func engineBesideTheNotch(safeFrom: CGFloat) -> TahoeEngine {
        let divider = self.divider
        return TahoeEngine(icons: icons, windows: bar, poster: bar, activity: IdlePerson(), makeDivider: { divider },
                           isOnScreen: { $0.maxX > 0 && $0.minX < SimulatedBar.screenWidth }, isSafeDrop: { $0 >= safeFrom },
                           pause: instant)
    }

    /// Opens `id` from the drawer at window 50, closes its menu, and waits until the divider is wide again.
    func openAndClose(_ id: IconID, pid: pid_t, with engine: TahoeEngine) async throws {
        let bar = self.bar
        icons.onPress = { _ in bar.openMenuOwners = [pid] }
        try await engine.open(id, anchor: bar.frame(50)!)
        #expect(bar.order.firstIndex(of: id.bundleID)! > bar.order.firstIndex(of: "|")!, "shown next to its drawer")
        bar.openMenuOwners = []
        let deadline = ContinuousClock.now + .seconds(5)
        while !(bar.order.firstIndex(of: id.bundleID)! < bar.order.firstIndex(of: "|")! && divider.isExpanded),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Seen on a real, crowded menu bar: Pli's own place, left of Claude, was beside the notch; it came back right
    /// behind the divider, and Claude and Pli swapped. Claude now comes out and goes back behind it: the order holds.
    @Test func anIconGoesBackToItsExactPlaceEvenBesideTheNotch() async throws {
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tiroir", key: "drawer", width: 30, pid: 1), at: 2)
        let engine = engineBesideTheNotch(safeFrom: 1200)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop"]))
        let hidden = bar.order
        #expect(hidden == ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "|", "com.protonmail.bridge", "com.google.drivefs",
                           "ch.rubencatalao.tiroir"])
        try await openAndClose(IconID(bundleID: "ch.rubencatalao.pli"), pid: 2003, with: engine)
        #expect(bar.order == hidden, "back left of Claude, not right behind the divider")
        #expect(divider.isExpanded)
    }

    @Test func everyIconBetweenComesOutAndGoesBackInOrder() async throws {
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tiroir", key: "drawer", width: 30, pid: 1), at: 2)
        let engine = engineBesideTheNotch(safeFrom: 1200)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "com.protonmail.bridge"]))
        let hidden = bar.order
        #expect(hidden == ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "com.protonmail.bridge", "|", "com.google.drivefs",
                           "ch.rubencatalao.tiroir"])
        try await openAndClose(IconID(bundleID: "ch.rubencatalao.pli"), pid: 2003, with: engine)
        #expect(bar.order == hidden)
        #expect(divider.isExpanded)
    }

    /// When even the drops next to the divider would be beside the notch, the icon stays right behind the divider:
    /// hidden as it should be, and nothing that shows moves.
    @Test func anOrderOutOfReachLeavesTheIconHiddenRightBehindTheDivider() async throws {
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tiroir", key: "drawer", width: 30, pid: 1), at: 2)
        let engine = engineBesideTheNotch(safeFrom: 1250)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop"]))
        try await openAndClose(IconID(bundleID: "ch.rubencatalao.pli"), pid: 2003, with: engine)
        let order = bar.order, divided = order.firstIndex(of: "|")!
        #expect(Set(order.prefix(divided)) == ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop"])
        #expect(order.suffix(from: divided + 1) == ["com.protonmail.bridge", "com.google.drivefs", "ch.rubencatalao.tiroir"])
        #expect(divider.isExpanded)
    }

    /// Some apps keep a window up at all times (an island around the notch, a floating panel): it is not what the
    /// press opened, and does not keep the icon out.
    @Test func aWindowTheAppAlreadyHadDoesNotKeepItsIconOut() async throws {
        bar.entries.insert(SimulatedBar.Entry(windowID: 50, bundleID: "ch.rubencatalao.tiroir", key: "drawer", width: 30, pid: 1), at: 2)
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        bar.openMenuOwners = [2000]
        try await engine.open(IconID(bundleID: "com.google.drivefs"), anchor: bar.frame(50)!)
        let deadline = ContinuousClock.now + .seconds(3)
        while bar.order.firstIndex(of: "com.google.drivefs")! > bar.order.firstIndex(of: "|")!, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(bar.order.firstIndex(of: "com.google.drivefs")! < bar.order.firstIndex(of: "|")!)
    }

    @Test func aBusyPersonIsNeverFought() async {
        let busy = TahoeEngine(icons: icons, windows: bar, poster: bar,
                               activity: IdlePerson(secondsSincePointerMoved: 0, isMouseButtonDown: true),
                               makeDivider: { self.divider }, isOnScreen: { _ in true }, pause: instant)
        await busy.start()
        let report = await busy.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.postponed == [IconID(bundleID: "com.google.drivefs")], "left for later, not a failure")
        #expect(report.failed.isEmpty)
        #expect(report.tryAgainIn == TahoeEngine.afterAPause)
        #expect(bar.drags.isEmpty)
    }

    /// Seen on a real menu bar: after a relaunch, every move waited for a person who was not there (a modifier left
    /// held by another app), failed, and the divider widened anyway: the icons that should show disappeared.
    @Test func aBusyPersonAtLaunchLeavesEveryIconShowing() async {
        bar.placeDividerAtRightEnd()
        let busy = TahoeEngine(icons: icons, windows: bar, poster: bar, activity: IdlePerson(areModifiersDown: true),
                               makeDivider: { self.divider }, isOnScreen: { _ in true }, isSafeDrop: { _ in true }, pause: instant)
        await busy.start()
        let report = await busy.apply(plan(hiding: ["ch.rubencatalao.pli"]))
        #expect(!divider.isExpanded, "nothing hides while icons that should show are on the divider's left")
        #expect(bar.drags.isEmpty)
        #expect(Set(report.postponed) == [IconID(bundleID: "com.google.drivefs"), IconID(bundleID: "com.protonmail.bridge"),
                                          IconID(bundleID: "com.anthropic.claudefordesktop")])
        #expect(report.tryAgainIn == TahoeEngine.afterAPause)
    }

    @Test func aFailedMoveNeverHidesAnIconThatShouldShow() async {
        bar.placeDividerAtRightEnd()
        await engine.start()
        bar.ignoresDrags = true
        let report = await engine.apply(plan(hiding: ["ch.rubencatalao.pli"]))
        #expect(!divider.isExpanded)
        #expect(!report.failed.isEmpty)
        #expect(report.tryAgainIn == TahoeEngine.retryAfter)
        #expect(divider.placesRemembered == 0, "a place that leaves icons stranded is not kept")
    }

    @Test func automaticRetriesStop() async {
        await engine.start()
        bar.ignoresDrags = true
        var asked = 0
        for _ in 0..<6 where await engine.apply(plan(hiding: ["com.google.drivefs"])).tryAgainIn != nil { asked += 1 }
        #expect(asked == TahoeEngine.automaticRetryLimit)
    }

    /// After a launch the divider sits right of every icon: one drag of the divider replaces a drag per icon.
    @Test func oneDragOfTheDividerReplacesMany() async {
        bar.placeDividerAtRightEnd()
        await engine.start()
        #expect(bar.order == ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "com.protonmail.bridge", "com.google.drivefs", "|"])
        let report = await engine.apply(plan(hiding: ["ch.rubencatalao.pli"]))
        #expect(bar.drags.count == 1)
        #expect(bar.order == ["ch.rubencatalao.pli", "|", "com.anthropic.claudefordesktop", "com.protonmail.bridge", "com.google.drivefs"])
        #expect(Set(report.moved) == [IconID(bundleID: "com.anthropic.claudefordesktop"), IconID(bundleID: "com.protonmail.bridge"),
                                      IconID(bundleID: "com.google.drivefs")], "the icons that now show")
        #expect(divider.isExpanded)
        #expect(divider.placesRemembered == 1)
    }

    @Test func theDividerStaysWhereItIsWhenMovingItSavesNothing() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.anthropic.claudefordesktop"]))
        #expect(bar.order == ["ch.rubencatalao.pli", "com.anthropic.claudefordesktop", "|", "com.protonmail.bridge", "com.google.drivefs"]
                || bar.order == ["com.anthropic.claudefordesktop", "|", "ch.rubencatalao.pli", "com.protonmail.bridge", "com.google.drivefs"])
        #expect(bar.drags.count == 2)
    }

    @Test func theDividerNeverGoesNearTheNotch() {
        // Right to left; true when the icon should show.
        let entries: [(String, CGFloat, Bool)] = [("a", 1300, true), ("b", 1260, true), ("c", 1220, false), ("d", 1180, true),
                                                  ("e", 1140, true), ("f", 900, true), ("g", 860, false)]
        let icons = entries.enumerated().map { index, entry in
            MenuBarIcon(id: IconID(bundleID: entry.0), ownerName: entry.0, frame: CGRect(x: entry.1, y: 0, width: 36, height: 33),
                        windowID: UInt32(10 + index), pid: 1)
        }
        let plan = VisibilityPlan(visible: Set(entries.filter(\.2).map { IconID(bundleID: $0.0) }),
                                  concealed: Set(entries.filter { !$0.2 }.map { IconID(bundleID: $0.0) }), hiddenApps: [])
        let rightEnd = CGRect(x: 1400, y: 0, width: 40, height: 33)
        // Anywhere, left of f is best: one drag of the divider, then c hides (two), instead of five icons carried.
        let anywhere = TahoeEngine.bestCut(icons: icons, plan: plan, dividerFrame: rightEnd, isSafeDrop: { _ in true })
        #expect(anywhere == .leftOf(icons[5].frame, windowID: 15))
        // Beside a notch that ends at 920, that place is out: left of b, the rightmost of the next best.
        let besideTheNotch = TahoeEngine.bestCut(icons: icons, plan: plan, dividerFrame: rightEnd, isSafeDrop: { $0 >= 980 })
        #expect(besideTheNotch == .leftOf(icons[1].frame, windowID: 11))
        // Already in its best place: no drag.
        let inPlace = CGRect(x: 880, y: 0, width: 16, height: 33)
        #expect(TahoeEngine.bestCut(icons: icons, plan: plan, dividerFrame: inPlace, isSafeDrop: { _ in true }) == nil)
    }

    @Test func aDividerBesideTheNotchMovesToAClearPlace() {
        // Right to left, side by side; the divider sits between c and d.
        let entries: [(String, CGFloat, Bool)] = [("a", 1300, true), ("b", 1264, true), ("c", 1228, true), ("d", 1152, true),
                                                  ("e", 1116, false)]
        let icons = entries.enumerated().map { index, entry in
            MenuBarIcon(id: IconID(bundleID: entry.0), ownerName: entry.0, frame: CGRect(x: entry.1, y: 0, width: 36, height: 33),
                        windowID: UInt32(10 + index), pid: 1)
        }
        let plan = VisibilityPlan(visible: Set(entries.filter(\.2).map { IconID(bundleID: $0.0) }),
                                  concealed: [IconID(bundleID: "e")], hiddenApps: [])
        let divider = CGRect(x: 1188, y: 0, width: 40, height: 33)
        // Clear of the notch, carrying d across is the fewest drags: the divider stays.
        #expect(TahoeEngine.bestCut(icons: icons, plan: plan, dividerFrame: divider, isSafeDrop: { _ in true }) == nil)
        // Beside it, no drop lands next to the divider: it moves to the nearest clear place, left of b.
        #expect(TahoeEngine.bestCut(icons: icons, plan: plan, dividerFrame: divider, isSafeDrop: { $0 >= 1240 })
                == .leftOf(icons[1].frame, windowID: 11))
    }

    @Test func aDropBesideTheNotchIsNeverTried() async {
        await engine.start()
        let mover = ItemMover(windows: bar, poster: bar, activity: IdlePerson(), isSafeDrop: { _ in false }, pause: instant)
        let drive = bar.frame(100)!
        await #expect(throws: EngineError.self) {
            try await mover.move(windowID: 103, ownerPID: 1, to: .rightOf(drive, windowID: 100))
        }
        #expect(bar.drags.isEmpty)
    }

    @Test func islandAppsAroundTheNotchAreKeptClearOf() {
        let windows = [
            DropZone.Overlay(layer: 27, frame: CGRect(x: 659, y: 0, width: 193, height: 32), ownerPID: 10),   // over the notch
            DropZone.Overlay(layer: 28, frame: CGRect(x: 529, y: 32, width: 453, height: 180), ownerPID: 11), // right under the bar
            DropZone.Overlay(layer: 101, frame: CGRect(x: 1100, y: 33, width: 250, height: 300), ownerPID: 12), // a menu
            DropZone.Overlay(layer: 28, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), ownerPID: 13),  // across the screen
            DropZone.Overlay(layer: 28, frame: CGRect(x: 1200, y: 0, width: 100, height: 32), ownerPID: 99),  // Tiroir's own
            DropZone.Overlay(layer: 3, frame: CGRect(x: 1300, y: 0, width: 100, height: 32), ownerPID: 14),   // an ordinary window
            DropZone.Overlay(layer: 28, frame: CGRect(x: 600, y: 300, width: 100, height: 100), ownerPID: 15), // far below the bar
        ]
        #expect(DropZone.overlayStart(windows, barHeight: 33, screenWidth: 1512, ownPID: 99) == 1022)
        #expect(DropZone.overlayStart([], barHeight: 33, screenWidth: 1512, ownPID: 99) == 0)
    }

    /// Seen on a real menu bar: Focus asked right after the divider widened found nothing to hide, because AppKit still
    /// gave the divider its old origin with its new width, far right of where it was.
    @Test func aDividerFrameAppKitHasNotCaughtUpWithIsNotBelieved() async {
        await engine.start()
        _ = await engine.apply(plan(hiding: ["ch.rubencatalao.pli"]))
        divider.lagsBehind = true
        let everything: Set<String> = ["com.google.drivefs", "com.protonmail.bridge", "com.anthropic.claudefordesktop", "ch.rubencatalao.pli"]
        let report = await engine.apply(plan(hiding: everything))
        #expect(report.moved.count == 3)
        #expect(bar.order.last == "|", "every icon hidden")
    }

    /// Seen on a real Mac: the screenshot tool kept a window over the whole screen at the menu bar's level for hours,
    /// and every icon stayed shown, waiting for that "menu" to close.
    @Test func anOverlayAcrossTheScreenIsNoMenu() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow)), barLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        #expect(SystemStatusWindows.isMenu(layer: menuLevel, frame: CGRect(x: 933, y: 35, width: 320, height: 366), displays: [screen]))
        #expect(SystemStatusWindows.isMenu(layer: barLevel, frame: CGRect(x: 1100, y: 33, width: 300, height: 400), displays: [screen]))
        #expect(!SystemStatusWindows.isMenu(layer: barLevel, frame: screen, displays: [screen]), "the screenshot tool's overlay")
        #expect(!SystemStatusWindows.isMenu(layer: barLevel, frame: CGRect(x: 1200, y: 0, width: 40, height: 33), displays: [screen]),
                "an icon")
    }

    @Test func aModifierHeldWithNoKeyEventIsNotAPerson() {
        #expect(SystemUserActivity.isPersonHolding(modifiers: true, secondsSinceKeyEvent: 0.5))
        #expect(!SystemUserActivity.isPersonHolding(modifiers: true, secondsSinceKeyEvent: 750))
        #expect(!SystemUserActivity.isPersonHolding(modifiers: false, secondsSinceKeyEvent: 0.5))
    }
}

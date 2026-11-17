import AppKit
import Testing
import TiroirCore
@testable import TiroirSystem

@MainActor
final class FakeRestriction: RestrictionControlling {
    var isAvailable = true
    var refuses = false
    private(set) var appliedAllowList: [String]?
    private(set) var applied: [[String]] = []
    private(set) var releases = 0

    func apply(allowed: [String]) async -> Error? {
        applied.append(allowed)
        if refuses { return RestrictionError.noAnswer }
        appliedAllowList = allowed
        return nil
    }

    func release() {
        appliedAllowList = nil
        releases += 1
    }
}

/// What MenuBarAgent would draw: every app with an icon, minus the apps the restriction leaves out.
final class FakeAgent: @unchecked Sendable {
    var apps: [String] = []
    weak var restriction: FakeRestriction?
    var drawn: [String] {
        MainActor.assumeIsolated {
            let allowed = restriction?.appliedAllowList.map(Set.init)
            return apps.filter { allowed?.contains($0) ?? true }
        }
    }
    func layout() -> AgentLayout {
        var x: CGFloat = 1300
        let items = drawn.map { bundleID -> AgentLayout.Item in
            x -= 36
            return AgentLayout.Item(bundleID: bundleID, systemIdentifier: nil, frame: CGRect(x: x, y: 0, width: 32, height: 33),
                                    pid: 3000, element: nil, isOverflowButton: false)
        }
        let clock = AgentLayout.Item(bundleID: nil, systemIdentifier: AgentLayout.clockIdentifier,
                                     frame: CGRect(x: 1363, y: 0, width: 151, height: 33), pid: 1, element: nil, isOverflowButton: false)
        return AgentLayout(displays: [AgentLayout.Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), items: [clock] + items)], agentPID: 1)
    }
}

@MainActor
final class FixedIcons: IconSource {
    var isTrusted = true
    let apps: [String]
    private(set) var pressed: [String] = []
    /// Called with the bundle identifier of each icon pressed: a test opens its menu there.
    var onPress: ((String) -> Void)?
    init(apps: [String]) { self.apps = apps }
    func find() async -> [FoundIcon] {
        apps.enumerated().map { index, bundleID in
            let recorder = Recorder(owner: self)
            return FoundIcon(app: RunningApp(pid: pid_t(3000 + index), bundleID: bundleID, name: bundleID),
                             frame: CGRect(x: 1000 - CGFloat(index) * 40, y: 0, width: 32, height: 33),
                             press: { recorder.press(bundleID) })
        }
    }
    final class Recorder: @unchecked Sendable {
        weak var owner: FixedIcons?
        init(owner: FixedIcons) { self.owner = owner }
        func press(_ bundleID: String) -> Bool {
            MainActor.assumeIsolated {
                owner?.pressed.append(bundleID)
                owner?.onPress?(bundleID)
            }
            return true
        }
    }
}

final class NoWindows: StatusWindowSource, @unchecked Sendable {
    var menusOpen = false
    func statusWindows() -> [StatusWindow] { [] }
    func raisedWindows(ownerPIDs: Set<pid_t>) -> Set<UInt32> { menusOpen ? [5000] : [] }
}

@MainActor
@Suite struct GoldenGateEngineTests {
    let restriction = FakeRestriction()
    let agent = FakeAgent()
    let icons = FixedIcons(apps: ["com.google.drivefs", "com.protonmail.bridge", "com.anthropic.claudefordesktop"])
    let windows = NoWindows()
    let clock = ClockZoneGuard()
    let running = ["com.google.drivefs", "com.protonmail.bridge", "com.anthropic.claudefordesktop", "com.apple.finder", "com.apple.controlcenter"]

    func engine(inApplications: Bool = true) -> GoldenGateEngine {
        let agent = self.agent
        agent.apps = ["com.google.drivefs", "com.protonmail.bridge", "com.anthropic.claudefordesktop"]
        agent.restriction = restriction
        return GoldenGateEngine(
            icons: icons, restriction: restriction, windows: windows, clock: clock,
            isInApplications: { inApplications }, runningBundleIDs: { self.running },
            readAgent: { agent.layout() }, readSettled: { _ in await MainActor.run { agent.layout() } }, pause: instant)
    }

    func plan(hiding bundleIDs: Set<String>) -> VisibilityPlan {
        VisibilityPlan(concealed: Set(bundleIDs.map { IconID(bundleID: $0) }), hiddenApps: bundleIDs)
    }

    @Test func hidingSendsEveryOtherRunningAppAsTheAllowList() async {
        let engine = engine()
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        let allowed = restriction.appliedAllowList ?? []
        #expect(!allowed.contains("com.google.drivefs"))
        #expect(allowed.contains("com.protonmail.bridge"))
        #expect(allowed.contains("com.apple.finder"), "apps without icons are allowed too, so their icons show when they add one")
        #expect(allowed.contains("com.apple.MenuBarAgent"))
        #expect(allowed == allowed.sorted())
        #expect(clock.isActive)
        clock.stop()
    }

    @Test func appleAgentsAreNeverHidden() async {
        let engine = engine()
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.apple.controlcenter"]))
        #expect(restriction.appliedAllowList == nil, "nothing hideable asked: no restriction and no side effects")
    }

    @Test func nothingToHideReleasesTheRestriction() async {
        let engine = engine()
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        _ = await engine.apply(plan(hiding: []))
        #expect(restriction.appliedAllowList == nil)
        #expect(!clock.isActive)
    }

    @Test func releasesWhileOverTheClockAndRestoresAfterLeaving() async {
        let engine = engine()
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        clock.onChange?(true)
        #expect(restriction.appliedAllowList == nil, "Notification Center can open")
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(restriction.appliedAllowList == nil, "no restriction comes back while the pointer rests on the clock")
        clock.onChange?(false)
        for _ in 0..<20 where restriction.appliedAllowList == nil { await Task.yield() }
        #expect(restriction.appliedAllowList?.contains("com.google.drivefs") == false)
        clock.stop()
    }

    @Test func restoreInvalidatesTheAssertion() async {
        let engine = engine()
        await engine.start()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        engine.restore()
        #expect(restriction.appliedAllowList == nil)
        #expect(!clock.isActive)
    }

    @Test func outsideApplicationsNothingIsHidden() async {
        let engine = engine(inApplications: false)
        await engine.start()
        #expect(engine.status == .needsApplicationsFolder)
        _ = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(restriction.applied.isEmpty)
    }

    @Test func withoutTheFrameworkTheEngineSaysSo() async {
        restriction.isAvailable = false
        let engine = engine()
        await engine.start()
        #expect(engine.status == .unavailable("MenuBarClientCore"))
    }

    @Test func aRefusedRestrictionIsReported() async {
        restriction.refuses = true
        let engine = engine()
        await engine.start()
        let report = await engine.apply(plan(hiding: ["com.google.drivefs"]))
        #expect(report.failed == [IconID(bundleID: "com.google.drivefs")])
    }

    @Test func aDrawnIconIsPressedWithoutTouchingTheRestriction() async throws {
        let engine = engine()
        await engine.start()
        _ = await engine.scan()
        try await engine.open(IconID(bundleID: "com.anthropic.claudefordesktop"), anchor: nil)
        #expect(icons.pressed == ["com.anthropic.claudefordesktop"])
        #expect(restriction.applied.isEmpty)
    }

    @Test func aHiddenAppIsLetThroughForItsMenuThenHiddenAgain() async throws {
        let engine = engine()
        engine.rehideDelay = 0
        await engine.start()
        _ = await engine.scan()
        _ = await engine.apply(plan(hiding: ["com.google.drivefs", "com.protonmail.bridge"]))
        #expect(!agent.drawn.contains("com.google.drivefs"))
        let hidingApplies = restriction.applied.count
        let windows = self.windows
        icons.onPress = { _ in windows.menusOpen = true }
        try await engine.open(IconID(bundleID: "com.google.drivefs"), anchor: nil)
        #expect(icons.pressed == ["com.google.drivefs"])
        #expect(restriction.applied.count == hidingApplies + 1)
        #expect(restriction.appliedAllowList?.contains("com.google.drivefs") == true, "let through for its menu")
        #expect(restriction.appliedAllowList?.contains("com.protonmail.bridge") == false, "the others stay hidden")
        try await Task.sleep(for: .milliseconds(60))
        #expect(restriction.applied.count == hidingApplies + 1, "still let through while the menu is open")
        windows.menusOpen = false
        for _ in 0..<80 where restriction.applied.count < hidingApplies + 2 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(restriction.appliedAllowList?.contains("com.google.drivefs") == false, "hidden again once the menu closed")
        clock.stop()
    }
}

import AppKit
@testable import ColShell
import Foundation
import Testing
import TiroirCore

/// The drawers as the option starts and stops them, in a test: it records what is asked of it and never touches the
/// menu bar.
@MainActor
private final class FakeRunner: DrawersRunner {
    var stops = 0
    var opened: [DrawersPane?] = []
    var sorts = 0
    var issue: DrawersIssue?
    var ownItemFrames: [CGRect] = []
    var drawerCount = 0

    func stop() { stops += 1 }
    func openSettings(_ pane: DrawersPane?) { opened.append(pane) }
    func showSmartSort() { sorts += 1 }
}

/// Preferences of their own, in the temporary folder: a name that is an absolute path keeps the domain in that file, so
/// nothing reaches ~/Library/Preferences.
private final class ScratchDefaults {
    let name: String
    let defaults: UserDefaults

    init() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "col-drawers-tests", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        name = folder.appending(path: UUID().uuidString).path
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(atPath: name + ".plist")
    }
}

/// One option with everything it reaches replaced: Col's preferences, Tiroir's, the running apps and the workspace's
/// notifications.
@MainActor
private final class Harness {
    let col = ScratchDefaults()
    let tiroir = ScratchDefaults()
    var running: [String] = ["com.apple.finder"]
    var supported = true
    let workspace = NotificationCenter()
    private(set) var runners: [FakeRunner] = []
    private(set) lazy var drawers = MenuBarDrawers(
        defaults: col.defaults, isSupported: supported, runningBundleIDs: { [unowned self] in running },
        standaloneSettings: { [tiroir] in tiroir.defaults }, workspace: workspace,
        makeRunner: { [unowned self] _ in
            let runner = FakeRunner()
            runners.append(runner)
            return runner
        })

    var runner: FakeRunner? { drawers.runner as? FakeRunner }

    /// Tiroir launched or quit, as NSWorkspace says it.
    func tiroir(_ name: Notification.Name, _ bundleID: String = TiroirInfo.bundleIdentifier) async {
        if name == NSWorkspace.didLaunchApplicationNotification { running.append(bundleID) } else { running.removeAll { $0 == bundleID } }
        workspace.post(name: name, object: nil, userInfo: ["bundleIdentifier": bundleID])
        // The observers hear it on the main queue.
        try? await Task.sleep(for: .milliseconds(30))
    }
}

@MainActor
@Suite struct MenuBarDrawersTests {
    // MARK: On and off

    /// Col's rule: with the switch off, nothing of the drawers runs, not even an observer.
    @Test func offByDefaultNothingRuns() {
        let harness = Harness()
        harness.drawers.start()
        #expect(!harness.drawers.isEnabled)
        #expect(harness.drawers.status == .off)
        #expect(harness.drawers.runner == nil)
        #expect(harness.drawers.observerCount == 0)
        #expect(harness.runners.isEmpty)
    }

    @Test func turningItOnStartsTheDrawersAndOffGivesEveryIconBack() {
        let harness = Harness()
        harness.drawers.setEnabled(true)
        #expect(harness.drawers.status == .running)
        #expect(harness.runners.count == 1)
        #expect(harness.drawers.observerCount == 2)
        #expect(harness.col.defaults.bool(forKey: MenuBarDrawers.enabledKey))

        let runner = harness.runner
        harness.drawers.setEnabled(false)
        #expect(runner?.stops == 1)
        #expect(harness.drawers.runner == nil)
        #expect(harness.drawers.status == .off)
        #expect(harness.drawers.observerCount == 0)
        #expect(!harness.col.defaults.bool(forKey: MenuBarDrawers.enabledKey))
    }

    @Test func turningItOnTwiceStartsOneSetOfDrawers() {
        let harness = Harness()
        harness.drawers.setEnabled(true)
        harness.drawers.setEnabled(true)
        harness.drawers.start()
        #expect(harness.runners.count == 1)
        #expect(harness.drawers.observerCount == 2)
    }

    @Test func onAtLaunchTheDrawersStartWithCol() {
        let harness = Harness()
        harness.col.defaults.set(true, forKey: MenuBarDrawers.enabledKey)
        harness.drawers.start()
        #expect(harness.drawers.status == .running)
        #expect(harness.runners.count == 1)
    }

    /// Quitting gives every icon back, and the switch stays on for the next launch.
    @Test func quittingColStopsTheDrawersAndKeepsTheSwitch() {
        let harness = Harness()
        harness.drawers.setEnabled(true)
        let runner = harness.runner
        harness.drawers.stop()
        #expect(runner?.stops == 1)
        #expect(harness.drawers.runner == nil)
        #expect(harness.drawers.observerCount == 0)
        #expect(harness.drawers.isEnabled)
    }

    @Test func beforeMacOS26TheSwitchDoesNothing() {
        let harness = Harness()
        harness.supported = false
        harness.drawers.setEnabled(true)
        #expect(harness.drawers.status == .needsNewerMacOS)
        #expect(harness.runners.isEmpty)
        #expect(harness.drawers.observerCount == 0)
    }

    // MARK: The standalone app

    @Test func theStandaloneAppIsKnownByEveryName() {
        #expect(MenuBarDrawers.isStandalone("ch.rubencatalao.tiroir"))
        #expect(MenuBarDrawers.isStandalone("ch.rubencatalao.tiroir.debug"))
        #expect(MenuBarDrawers.isStandalone("ch.rubencatalao.tansu"))
        #expect(!MenuBarDrawers.isStandalone("ch.rubencatalao.tiroirs"))
        #expect(!MenuBarDrawers.isStandalone("ch.rubencatalao.islet"))
    }

    /// Two apps arranging the same icons undo each other's work: while Tiroir runs, Col waits, and takes over once it
    /// quits.
    @Test func whileTiroirRunsColWaitsThenTakesOver() async {
        let harness = Harness()
        harness.running.append(TiroirInfo.bundleIdentifier)
        harness.drawers.setEnabled(true)
        #expect(harness.drawers.status == .yieldsToTiroir)
        #expect(harness.runners.isEmpty)
        #expect(harness.drawers.observerCount == 2)

        await harness.tiroir(NSWorkspace.didTerminateApplicationNotification)
        #expect(harness.drawers.status == .running)
        #expect(harness.runners.count == 1)
    }

    @Test func whenTiroirOpensColStepsAside() async {
        let harness = Harness()
        harness.drawers.setEnabled(true)
        let runner = harness.runner
        await harness.tiroir(NSWorkspace.didLaunchApplicationNotification)
        #expect(runner?.stops == 1)
        #expect(harness.drawers.runner == nil)
        #expect(harness.drawers.status == .yieldsToTiroir)
    }

    @Test func otherAppsComingAndGoingChangeNothing() async {
        let harness = Harness()
        harness.drawers.setEnabled(true)
        await harness.tiroir(NSWorkspace.didLaunchApplicationNotification, "com.example.notes")
        #expect(harness.drawers.status == .running)
        #expect(harness.runners.count == 1)
    }

    @Test func offTiroirQuittingStartsNothing() async {
        let harness = Harness()
        harness.running.append(TiroirInfo.bundleIdentifier)
        harness.drawers.setEnabled(true)
        harness.drawers.setEnabled(false)
        await harness.tiroir(NSWorkspace.didTerminateApplicationNotification)
        #expect(harness.drawers.status == .off)
        #expect(harness.runners.isEmpty)
    }

    // MARK: Tiroir's settings

    static func tiroirSettings() -> Data {
        var settings = TiroirSettings.defaults
        settings.hasCompletedWelcome = true
        settings.layout = Layout(drawers: [Drawer(name: "Files & Cloud", mark: .symbol("cloud.fill"), category: .files)])
        return SettingsStore.data(settings)!
    }

    /// A Tiroir user finds the same drawers: the first time the drawers start, Tiroir's settings and the places of its
    /// items come along.
    @Test func theFirstTimeTiroirsSettingsComeAlong() {
        let harness = Harness()
        let data = Self.tiroirSettings()
        harness.tiroir.defaults.set(data, forKey: TiroirInfo.settingsKey)
        harness.tiroir.defaults.set(412.0, forKey: "NSStatusItem Preferred Position tiroir.divider")
        harness.tiroir.defaults.set(3.0, forKey: "NSStatusItem Preferred Position tiroir.drawer.6F0C2D1E-0000-0000-0000-000000000001")
        harness.tiroir.defaults.set(400.0, forKey: "tiroir.divider.position")
        harness.tiroir.defaults.set(9.0, forKey: "NSStatusItem Preferred Position com.example.other")
        harness.tiroir.defaults.set(true, forKey: "SUEnableAutomaticChecks")
        harness.drawers.setEnabled(true)

        let col = harness.col.defaults
        #expect(harness.drawers.importedFromTiroir)
        #expect(col.data(forKey: MenuBarDrawers.settingsKey) == data)
        #expect(col.double(forKey: "NSStatusItem Preferred Position tiroir.divider") == 412)
        #expect(col.double(forKey: "NSStatusItem Preferred Position tiroir.drawer.6F0C2D1E-0000-0000-0000-000000000001") == 3)
        #expect(col.double(forKey: "tiroir.divider.position") == 400)
        #expect(col.object(forKey: "NSStatusItem Preferred Position com.example.other") == nil)
        #expect(col.object(forKey: "SUEnableAutomaticChecks") == nil)
        // The imported settings read back as drawers.
        let loaded = SettingsStore(defaults: col, key: MenuBarDrawers.settingsKey).load()
        #expect(loaded.outcome == .loaded)
        #expect(loaded.settings.layout.drawers.map(\.name) == ["Files & Cloud"])
        #expect(loaded.settings.hasCompletedWelcome)
    }

    /// Once Col has drawers of its own, Tiroir's never replace them.
    @Test func colsOwnDrawersStay() {
        let harness = Harness()
        let own = Data("{\"schemaVersion\":1}".utf8)
        harness.col.defaults.set(own, forKey: MenuBarDrawers.settingsKey)
        harness.tiroir.defaults.set(Self.tiroirSettings(), forKey: TiroirInfo.settingsKey)
        harness.drawers.setEnabled(true)
        #expect(!harness.drawers.importedFromTiroir)
        #expect(harness.col.defaults.data(forKey: MenuBarDrawers.settingsKey) == own)
    }

    @Test func settingsColCannotReadAreLeftWhereTheyAre() {
        let harness = Harness()
        harness.tiroir.defaults.set(Data("not json".utf8), forKey: TiroirInfo.settingsKey)
        harness.tiroir.defaults.set(412.0, forKey: "NSStatusItem Preferred Position tiroir.divider")
        harness.drawers.setEnabled(true)
        #expect(!harness.drawers.importedFromTiroir)
        #expect(harness.col.defaults.data(forKey: MenuBarDrawers.settingsKey) == nil)
        #expect(harness.col.defaults.object(forKey: "NSStatusItem Preferred Position tiroir.divider") == nil)
        // Without Tiroir's settings the drawers start afresh, with their welcome.
        #expect(harness.drawers.status == .running)
    }

    @Test func withoutTiroirTheDrawersStartAfresh() {
        let harness = Harness()
        harness.drawers.setEnabled(true)
        #expect(!harness.drawers.importedFromTiroir)
        #expect(harness.drawers.status == .running)
    }

    @Test func onlyTheDrawersItemPlacesCount() {
        #expect(MenuBarDrawers.isItemPlace("NSStatusItem Preferred Position tiroir.main"))
        #expect(MenuBarDrawers.isItemPlace("NSStatusItem Visible tiroir.divider"))
        #expect(MenuBarDrawers.isItemPlace("tiroir.divider.position"))
        #expect(!MenuBarDrawers.isItemPlace("NSStatusItem Preferred Position Item-0"))
        #expect(!MenuBarDrawers.isItemPlace("settings"))
    }

    // MARK: The pane

    @Test func thePaneOpensTheDrawersSettings() {
        let harness = Harness()
        harness.drawers.setEnabled(true)
        harness.drawers.runner?.openSettings(.layout)
        harness.drawers.runner?.showSmartSort()
        #expect(harness.runner?.opened == [.layout])
        #expect(harness.runner?.sorts == 1)
    }

    @Test func theMenuBarPaneIsFoundByItsWords() {
        #expect(SettingsPane.menuBar.group == .modules)
        #expect(SettingsPane.menuBar.matches("drawers"))
        #expect(SettingsPane.menuBar.matches("Tiroir"))
        #expect(SettingsPane.menuBar.matches("Smart Sort"))
    }
}

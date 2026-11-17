import AppKit
import Observation
import TiroirCore

/// The panes of the drawers' own settings window.
enum DrawersPane: String, CaseIterable {
    case layout, drawers, profiles, triggers, appearance, behavior, shortcuts, general
}

/// Why drawers that are on cannot do their work right now.
enum DrawersIssue: Equatable {
    /// Accessibility (Device Control and Data Access on macOS 27) is not granted: every icon shows.
    case needsPermission
    /// macOS 27 honours only apps that run from /Applications.
    case needsApplicationsFolder
    /// A private function the engine needs is missing on this macOS: every icon shows.
    case unavailable(String)
}

/// What runs while the option is on: the drawers themselves, or a stand-in in tests.
@MainActor
protocol DrawersRunner: AnyObject {
    /// Gives every icon back and stops everything the drawers started. Synchronous and quick: Col calls it as it quits.
    func stop()
    func openSettings(_ pane: DrawersPane?)
    /// Smart Sort again, from the welcome's first step.
    func showSmartSort()
    /// The drawers' own items, in AppKit coordinates.
    var ownItemFrames: [CGRect] { get }
    var issue: DrawersIssue? { get }
    var drawerCount: Int { get }
}

/// Col's menu bar option: the icons of the menu bar tidied into drawers, by the drawers of Tiroir, which run in Col's
/// process from the moment the switch is on.
///
/// Off, nothing of it runs: no observer, no timer, no monitor, and the drawers' code and the private framework they use
/// on macOS 27 are never reached. On, it starts the drawers, unless the standalone Tiroir app runs: two apps arranging
/// the same icons would undo each other's work, so Col waits for Tiroir to quit. The first time, Tiroir's own settings
/// come along, so a Tiroir user finds the same drawers. Turned off, when Col quits and when it relaunches, every icon
/// comes back; after a crash too, since the drawers' divider and restriction end with Col's process.
@MainActor
@Observable
final class MenuBarDrawers {
    static let shared = MenuBarDrawers()

    enum Status: Equatable {
        /// The switch is off.
        case off
        /// macOS 26 or later is needed.
        case needsNewerMacOS
        /// The standalone Tiroir app runs and arranges the menu bar.
        case yieldsToTiroir
        case running
    }

    /// Where the switch and the drawers' settings live, in Col's preferences.
    static let enabledKey = "tidiesMenuBar"
    static let settingsKey = "menuBarDrawers"

    private(set) var status: Status = .off
    /// The drawers, while they run.
    private(set) var runner: DrawersRunner?
    /// Whether Tiroir's settings came along when the drawers first started.
    private(set) var importedFromTiroir = false

    /// The menu bar changed: Col measures the room beside the notch again.
    @ObservationIgnored var menuBarChanged: (() -> Void)?
    /// Moves Col to /Applications and opens it from there (macOS 27 honours only apps there). Set by the app.
    @ObservationIgnored var moveToApplications: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isSupported: Bool
    @ObservationIgnored private let runningBundleIDs: () -> [String]
    @ObservationIgnored private let standaloneSettings: () -> UserDefaults?
    @ObservationIgnored private let workspace: NotificationCenter
    @ObservationIgnored private let makeRunner: (MenuBarDrawers) -> DrawersRunner?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var termination: DispatchSourceSignal?
    @ObservationIgnored private var pendingChange: DispatchWorkItem?

    init(
        defaults: UserDefaults = .standard,
        isSupported: Bool = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)),
        runningBundleIDs: @escaping () -> [String] = { NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) },
        standaloneSettings: @escaping () -> UserDefaults? = { UserDefaults(suiteName: TiroirInfo.bundleIdentifier) },
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        makeRunner: ((MenuBarDrawers) -> DrawersRunner?)? = nil
    ) {
        self.defaults = defaults
        self.isSupported = isSupported
        self.runningBundleIDs = runningBundleIDs
        self.standaloneSettings = standaloneSettings
        self.workspace = workspace
        self.makeRunner = makeRunner ?? { drawers in
            guard #available(macOS 26, *) else { return nil }
            return ColDrawersRunner(drawers: drawers)
        }
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var isSupportedHere: Bool { isSupported }
    /// Observers while the option is on: what the pane and the tests check is nothing at rest.
    var observerCount: Int { observers.count }

    // MARK: Lifecycle

    /// At launch: the drawers start if the switch is on.
    func start() {
        guard isEnabled else { return }
        activate()
    }

    /// The switch in Settings, Menu Bar.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled || (enabled && status == .off) else { return }
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled { activate() } else { deactivate() }
    }

    /// As Col quits: every icon comes back; the switch keeps its place for the next launch.
    func stop() {
        stopRunner()
        removeObservers()
    }

    private func activate() {
        guard isSupported else {
            status = .needsNewerMacOS
            return
        }
        watchTheStandaloneApp()
        if standaloneIsRunning {
            stopRunner()
            status = .yieldsToTiroir
            return
        }
        guard runner == nil else { return }
        importedFromTiroir = importTiroirSettingsIfNeeded()
        runner = makeRunner(self)
        status = runner == nil ? .needsNewerMacOS : .running
        if runner != nil { quitGracefullyOnTerminationSignal() }
    }

    private func deactivate() {
        stopRunner()
        removeObservers()
        status = .off
    }

    private func stopRunner() {
        guard let runner else { return }
        runner.stop()
        self.runner = nil
        termination?.cancel()
        termination = nil
        signal(SIGTERM, SIG_DFL)
    }

    // MARK: The standalone app

    /// Whether Tiroir (or Tansu, its name before 1.1) runs, in a release or a development build.
    var standaloneIsRunning: Bool {
        runningBundleIDs().contains(where: Self.isStandalone)
    }

    nonisolated static func isStandalone(_ bundleID: String) -> Bool {
        TiroirInfo.standaloneBundleIdentifiers.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    /// Asks Tiroir to quit, as its Quit command would: it gives every icon back, then Col's drawers take over.
    func quitStandalone() {
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier.map(Self.isStandalone) == true {
            app.terminate()
        }
    }

    /// While the option is on, and only then: Tiroir opening makes the drawers step aside, Tiroir quitting brings them
    /// back.
    private func watchTheStandaloneApp() {
        guard observers.isEmpty else { return }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                    ?? note.userInfo?["bundleIdentifier"] as? String
                guard let bundleID, Self.isStandalone(bundleID) else { return }
                MainActor.assumeIsolated { self?.standaloneChanged() }
            })
        }
    }

    func standaloneChanged() {
        guard isEnabled else { return }
        activate()
    }

    private func removeObservers() {
        for observer in observers { workspace.removeObserver(observer) }
        observers.removeAll()
    }

    // MARK: Tiroir's settings

    /// The first time the drawers start, Tiroir's settings come along, if it has any: its drawers, profiles, triggers and
    /// look, and the places of its items in the menu bar. Returns whether they did.
    func importTiroirSettingsIfNeeded() -> Bool {
        guard defaults.data(forKey: Self.settingsKey) == nil, let tiroir = standaloneSettings(),
              let data = tiroir.data(forKey: TiroirInfo.settingsKey),
              case .success = SettingsStore.read(data) else { return false }
        defaults.set(data, forKey: Self.settingsKey)
        for (key, value) in tiroir.dictionaryRepresentation() where Self.isItemPlace(key) {
            defaults.set(value, forKey: key)
        }
        return true
    }

    /// The places macOS keeps for the drawers' items and divider (`NSStatusItem Preferred Position tiroir.divider`…),
    /// and the copy the divider keeps of its own.
    nonisolated static func isItemPlace(_ key: String) -> Bool {
        (key.hasPrefix("NSStatusItem ") && key.contains(" tiroir.")) || key == "tiroir.divider.position"
    }

    // MARK: The island

    /// The drawers moved icons or changed their own items: the island measures the menu bar once they settle.
    func drawersChangedTheMenuBar() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.menuBarChanged?() }
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// The drawers' own items, for the island's measure of the menu bar.
    var ownItemFrames: [CGRect] { runner?.ownItemFrames ?? [] }

    /// `kill` quits Col like its Quit command while the drawers run, so the divider keeps its place for the next launch.
    /// Without the drawers, Col leaves the signal alone.
    private func quitGracefullyOnTerminationSignal() {
        guard termination == nil, NSApp != nil else { return }
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termination = source
    }
}

/// What the app target gives the menu bar option: it owns the code that moves Col to /Applications, which the drawers ask
/// for on macOS 27.
public enum MenuBarOption {
    @MainActor public static var moveToApplications: (() -> Void)? {
        get { MenuBarDrawers.shared.moveToApplications }
        set { MenuBarDrawers.shared.moveToApplications = newValue }
    }
}

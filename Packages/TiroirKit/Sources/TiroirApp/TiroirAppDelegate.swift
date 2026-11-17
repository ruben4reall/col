import AppKit
import TiroirSystem

/// Tiroir's application delegate. The app target subclasses it to add the Sparkle updater and the move to
/// /Applications, the only code that lives outside this package.
@MainActor
open class TiroirAppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var coordinator: Coordinator?
    private var termination: DispatchSourceSignal?

    public override init() {
        super.init()
    }

    /// The updater, provided by the app target.
    open func makeUpdater() -> UpdateChecking? { nil }

    /// Moves Tiroir to /Applications and relaunches it from there; the app target provides it.
    open func moveToApplications() {}

    /// Offers once to move Tiroir to /Applications; the app target provides it.
    open func offerToMoveToApplications() {}

    open func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        offerToMoveToApplications()
        let coordinator = Coordinator(options: .current(), updater: makeUpdater())
        coordinator.moveToApplicationsHandler = { [weak self] in self?.moveToApplications() }
        self.coordinator = coordinator
        quitOnTerminationSignal()
        Log.app.info("Tiroir started")
        Task { await coordinator.start() }
    }

    open func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }

    /// `kill` and `killall` quit Tiroir like its Quit command: the divider keeps its place and every setting it changed
    /// comes back.
    private func quitOnTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termination = source
    }

    /// Opening Tiroir again from Finder or Spotlight opens Settings.
    open func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.interface.actions.openSettings(.layout)
        return false
    }

    open func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

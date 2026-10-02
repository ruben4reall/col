import AppKit
import ColShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var updater: SparkleUpdater?
    /// A Col already running, a copy from elsewhere say: this one hands it what it was opened with, then leaves.
    private var other: NSRunningApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        other = Self.otherCol()
        // An older version still running, Islet 1 at login while Col 2 opens from the download: it makes way.
        if let running = other, let url = running.bundleURL, let bundle = Bundle(url: url), NameChange.isOlder(bundle, than: .main) {
            running.terminate()
            let deadline = Date().addingTimeInterval(3)
            while !running.isTerminated, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            other = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if other != nil {
            // Two islands on one notch is never right. A moment later, so that a link this copy was opened with
            // reaches the other first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            return
        }
        if NameChange.renameBundleIfNeeded() || ApplicationsFolder.offerToMoveIfNeeded() { return }
        NameChange.migrateIfNeeded()
        AppMenu.install()
        let updater = SparkleUpdater()
        self.updater = updater
        Updates.checker = updater
        let island = IslandController()
        island.start()
        self.island = island
    }

    func applicationWillTerminate(_ notification: Notification) {
        island?.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let other, let bundle = other.bundleURL {
            NSWorkspace.shared.open(urls, withApplicationAt: bundle, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { island?.importScripts(files) }
        urls.filter { !$0.isFileURL }.forEach { island?.open($0) }
    }

    /// The Col already running with this identifier, unless this one was given a socket of its own to run beside it.
    private static func otherCol() -> NSRunningApplication? {
        guard ProcessInfo.processInfo.environment["COL_SOCKET"]?.isEmpty ?? true, let identifier = Bundle.main.bundleIdentifier else {
            return nil
        }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
            $0.processIdentifier != me && !$0.isTerminated
        }
    }
}

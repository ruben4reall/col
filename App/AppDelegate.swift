import AppKit
import IsletShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var updater: SparkleUpdater?
    /// An Islet already running, a copy from elsewhere say: this one hands it what it was opened with, then leaves.
    private var other: NSRunningApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        other = Self.otherIslet()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if other != nil {
            // Two islands on one notch is never right. A moment later, so that a link this copy was opened with
            // reaches the other first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            return
        }
        if ApplicationsFolder.offerToMoveIfNeeded() { return }
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

    /// The Islet already running with this identifier, unless this one was given a socket of its own to run beside it.
    private static func otherIslet() -> NSRunningApplication? {
        guard ProcessInfo.processInfo.environment["ISLET_SOCKET"]?.isEmpty ?? true, let identifier = Bundle.main.bundleIdentifier else {
            return nil
        }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
            $0.processIdentifier != me && !$0.isTerminated
        }
    }
}

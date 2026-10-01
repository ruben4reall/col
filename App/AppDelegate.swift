import AppKit
import IsletShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var updater: SparkleUpdater?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { island?.importScripts(files) }
        urls.filter { !$0.isFileURL }.forEach { island?.open($0) }
    }
}

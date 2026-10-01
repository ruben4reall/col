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
        urls.forEach { island?.open($0) }
    }
}

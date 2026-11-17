import AppKit
import Foundation
import Testing
@testable import TiroirApp
import TiroirUI

/// The option turned off before the drawers had even started: they never start. Shut down before any start, nothing
/// touches the menu bar of the Mac that runs the tests, and the settings stay in the temporary folder.
@MainActor
@Suite struct ShutdownTests {
    @Test func drawersTurnedOffBeforeTheyStartNeverStart() async {
        let name = scratchDefaultsName()
        defer { discardDefaults(name) }
        let options = LaunchOptions(demo: false, welcomeStep: nil, settingsPane: nil, openDrawer: nil, search: nil, quiet: true,
                                    backdrop: nil)
        let coordinator = Coordinator(options: options, host: DrawersHost(defaults: UserDefaults(suiteName: name)!, settingsKey: "drawers"))
        coordinator.shutdown()
        await coordinator.start()
        #expect(coordinator.isShutDown)
        #expect(coordinator.interface.icons.isEmpty, "no scan after the shutdown")
        #expect(coordinator.ownItemFrames.isEmpty, "no item in the menu bar")
    }

    @Test func aShutdownTwiceIsOnce() {
        let name = scratchDefaultsName()
        defer { discardDefaults(name) }
        let options = LaunchOptions(demo: false, welcomeStep: nil, settingsPane: nil, openDrawer: nil, search: nil, quiet: true,
                                    backdrop: nil)
        var changes = 0
        let host = DrawersHost(defaults: UserDefaults(suiteName: name)!, settingsKey: "drawers", menuBarChanged: { changes += 1 })
        let coordinator = Coordinator(options: options, host: host)
        coordinator.shutdown()
        coordinator.shutdown()
        #expect(changes == 1)
    }
}

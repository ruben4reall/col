import Foundation
import Testing
@testable import TiroirApp
import TiroirUI

@Suite struct LaunchOptionsTests {
    final class Scratch {
        let name = scratchDefaultsName()
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { discardDefaults(name) }
    }

    @Test func nothingSetMeansNormalLaunch() {
        let options = LaunchOptions.current(Scratch().defaults)
        #expect(!options.demo)
        #expect(options.welcomeStep == nil)
        #expect(options.openDrawer == nil)
        #expect(options.settingsPane == nil)
        #expect(!options.quiet)
    }

    /// The command line gives text (`-TiroirOpenDrawer 0`), `defaults write` gives numbers: both work.
    @Test func numbersArriveAsTextOrNumbers() {
        let scratch = Scratch()
        scratch.defaults.set("2", forKey: "TiroirWelcomeStep")
        scratch.defaults.set(0, forKey: "TiroirOpenDrawer")
        scratch.defaults.set("appearance", forKey: "TiroirSettingsPane")
        scratch.defaults.set(true, forKey: "TiroirDemo")
        let options = LaunchOptions.current(scratch.defaults)
        #expect(options.welcomeStep == 2)
        #expect(options.openDrawer == 0)
        #expect(options.settingsPane == .appearance)
        #expect(options.demo)
    }

    @Test func allOpensTheAllDrawer() {
        let scratch = Scratch()
        scratch.defaults.set("all", forKey: "TiroirOpenDrawer")
        #expect(LaunchOptions.current(scratch.defaults).openDrawer == -1)
    }
}

/// A name for a test's own preferences domain. A name that is an absolute path makes macOS keep the domain in that file,
/// here in the temporary folder: nothing reaches ~/Library/Preferences, even the empty file cfprefsd can write back
/// after a test has removed its domain.
func scratchDefaultsName() -> String {
    let folder = FileManager.default.temporaryDirectory.appending(path: "tiroir-tests", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: UUID().uuidString).path
}

/// Removes a preferences domain a test made with `scratchDefaultsName()`, and its file.
func discardDefaults(_ name: String) {
    UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    CFPreferencesAppSynchronize(name as CFString)
    try? FileManager.default.removeItem(atPath: name + ".plist")
}

import Foundation
import Testing
@testable import TiroirCore

@Suite struct SettingsTests {
    /// A private preferences domain per test, removed afterwards.
    final class Scratch {
        let name = scratchDefaultsName()
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { discardDefaults(name) }
    }

    @Test func nothingStoredGivesTheDefaults() {
        let scratch = Scratch()
        let (settings, outcome) = SettingsStore(defaults: scratch.defaults).load()
        #expect(outcome == .fresh)
        #expect(settings == .defaults)
        #expect(settings.shortcuts.search == .defaultSearch)
        #expect(settings.shortcuts.focus == .defaultFocus)
        #expect(settings.shortcuts.allDrawer == nil)
        #expect(!settings.hasCompletedWelcome)
    }

    /// A test's preferences live in the temporary folder, never in ~/Library/Preferences, where each run of the tests
    /// used to leave empty files that cfprefsd wrote back after the test had removed its domain.
    @Test func scratchPreferencesLiveInTheTemporaryFolder() {
        let scratch = Scratch()
        #expect(scratch.name.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(!scratch.name.contains("Library/Preferences"))
        scratch.defaults.set(true, forKey: "written")
        CFPreferencesAppSynchronize(scratch.name as CFString)
        #expect(UserDefaults(suiteName: scratch.name)?.bool(forKey: "written") == true)
    }

    @Test func settingsSurviveARoundTrip() {
        let scratch = Scratch()
        let store = SettingsStore(defaults: scratch.defaults)
        var settings = TiroirSettings.defaults
        let drawer = Drawer(name: "Files & Cloud", mark: .emoji("☁️"), category: .files, showsCount: true)
        settings.layout.addDrawer(drawer)
        settings.layout.assign(IconID(bundleID: "com.google.drivefs"), to: .drawer(drawer.id))
        settings.appearance.tint = .gradient
        settings.behavior.opensOnHover = true
        settings.shortcuts.search = nil
        settings.userCategories["com.example.app"] = .ai
        settings.pinned = [IconID(bundleID: "com.apple.Spotlight")]
        settings.sortStrategy = .developer
        settings.hasCompletedWelcome = true
        store.save(settings)
        let (loaded, outcome) = store.load()
        #expect(outcome == .loaded)
        #expect(loaded == settings)
        #expect(loaded.shortcuts.search == nil, "a shortcut turned off stays off")
    }

    @Test func valuesAreClampedOnRead() throws {
        let scratch = Scratch()
        let json = #"{"schemaVersion": 1, "behavior": {"hoverDelay": 30, "rehideDelay": -4}, "appearance": {"opacity": 7}}"#
        scratch.defaults.set(Data(json.utf8), forKey: "settings")
        let (settings, outcome) = SettingsStore(defaults: scratch.defaults).load()
        #expect(outcome == .loaded)
        #expect(settings.behavior.hoverDelay == 1.0)
        #expect(settings.behavior.rehideDelay == 0)
        #expect(settings.appearance.opacity == 1)
    }

    @Test func anUnreadableValueFallsBackAndIsKept() {
        let scratch = Scratch()
        scratch.defaults.set(Data("not json".utf8), forKey: "settings")
        let (settings, outcome) = SettingsStore(defaults: scratch.defaults).load()
        #expect(outcome == .unreadable)
        #expect(settings == .defaults)
        #expect(scratch.defaults.data(forKey: "settings") == Data("not json".utf8))
    }

    @Test func settingsFromANewerTiroirAreLeftUntouched() {
        let scratch = Scratch()
        let json = Data(#"{"schemaVersion": 7, "hasCompletedWelcome": true}"#.utf8)
        scratch.defaults.set(json, forKey: "settings")
        let (settings, outcome) = SettingsStore(defaults: scratch.defaults).load()
        #expect(outcome == .newerVersion(7))
        #expect(settings == .defaults)
        #expect(scratch.defaults.data(forKey: "settings") == json)
    }

    @Test func missingKeysTakeTheirDefaults() throws {
        let settings = try JSONDecoder().decode(TiroirSettings.self, from: Data(#"{"hasCompletedWelcome": true}"#.utf8))
        #expect(settings.hasCompletedWelcome)
        #expect(settings.layout == .empty)
        #expect(settings.shortcuts.search == .defaultSearch)
        #expect(settings.userCategories.isEmpty)
    }

    @Test func anUnknownCategoryIsDropped() throws {
        let settings = try JSONDecoder().decode(TiroirSettings.self, from: Data(#"{"userCategories": {"a": "ai", "b": "future"}}"#.utf8))
        #expect(settings.userCategories == ["a": .ai])
    }

    @Test func resetForgetsEverything() {
        let scratch = Scratch()
        let store = SettingsStore(defaults: scratch.defaults)
        store.save(TiroirSettings(hasCompletedWelcome: true))
        store.reset()
        #expect(store.load().outcome == .fresh)
    }
}

@Suite struct ShortcutTests {
    @Test func shortcutsReadInApplesOrder() {
        #expect(Shortcut.defaultSearch.display == "⌃⌥⌘Space")
        #expect(Shortcut(keyCode: 3, modifiers: [.command, .shift, .option, .control], keyLabel: "F").display == "⌃⌥⇧⌘F")
    }

    @Test func aShortcutNeedsAModifierBesidesShift() {
        #expect(Shortcut.defaultFocus.isUsable)
        #expect(!Shortcut(keyCode: 3, modifiers: [.shift], keyLabel: "F").isUsable)
        #expect(!Shortcut(keyCode: 3, modifiers: [], keyLabel: "F").isUsable)
    }
}

@Suite struct ColorTests {
    @Test func hexReadsAndWrites() {
        let honey = RGBA(hex: "#FFB938")
        #expect(honey?.hex == "#FFB938")
        #expect(RGBA(hex: "FFB93880")?.alpha ?? 0 > 0.5)
        #expect(RGBA(hex: "#FFF") == nil)
        #expect(RGBA(hex: "#GGGGGG") == nil)
    }

    @Test func contrastFollowsWCAG() {
        let black = RGBA(red: 0, green: 0, blue: 0)
        let white = RGBA(red: 1, green: 1, blue: 1)
        #expect(abs(black.contrast(with: white) - 21) < 0.01)
        #expect(abs(white.contrast(with: white) - 1) < 0.01)
    }

    @Test func appearanceDrawsNothingByDefault() {
        #expect(!Appearance.standard.isVisible)
        #expect(Appearance(tint: .color).isVisible)
        #expect(Appearance(border: true).isVisible)
    }
}

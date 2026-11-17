import Foundation
import Testing
@testable import TiroirCore

@Suite struct BehaviorTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func settingsFromBeforeRevealOptionsKeepTheirValues() throws {
        let behavior = try decode(Behavior.self, #"{"opensOnHover": true, "hoverDelay": 0.4, "showsTiroirIcon": false}"#)
        #expect(behavior.opensOnHover)
        #expect(behavior.hoverDelay == 0.4)
        #expect(!behavior.showsTiroirIcon)
        #expect(!behavior.revealsOnHover && !behavior.revealsOnClick && !behavior.revealsOnScroll)
        #expect(!behavior.revealsFromTheMenuBar)
        #expect(behavior.revealPlace == .menuBar)
        #expect(behavior.hidesAgainAutomatically)
        #expect(behavior.hideAgainDelay == 5)
        #expect(!behavior.movesOverflowAutomatically)
    }

    @Test func anUnknownRevealPlaceFallsBackToTheMenuBar() throws {
        let behavior = try decode(Behavior.self, #"{"revealPlace": "somewhereNew", "revealsOnScroll": true}"#)
        #expect(behavior.revealPlace == .menuBar)
        #expect(behavior.revealsOnScroll)
        #expect(behavior.revealsFromTheMenuBar)
    }

    @Test func theHideAgainDelayStaysInItsRange() {
        #expect(Behavior(hideAgainDelay: 0).clamped.hideAgainDelay == 1)
        #expect(Behavior(hideAgainDelay: 300).clamped.hideAgainDelay == 30)
        #expect(Behavior(hideAgainDelay: 8).clamped.hideAgainDelay == 8)
    }

    @Test func behaviorSurvivesARoundTrip() throws {
        let behavior = Behavior(revealsOnHover: true, revealsOnClick: true, revealPlace: .allDrawer, hidesAgainAutomatically: false,
                                hideAgainDelay: 12, movesOverflowAutomatically: true)
        let data = try JSONEncoder().encode(behavior)
        #expect(try JSONDecoder().decode(Behavior.self, from: data) == behavior)
    }
}

@Suite struct IconShortcutTests {
    let drive = IconID(bundleID: "com.google.drivefs")
    let vpn = IconID(bundleID: "ch.protonvpn.mac")
    let keyD = Shortcut(keyCode: 2, modifiers: [.control, .option], keyLabel: "D")
    let keyV = Shortcut(keyCode: 9, modifiers: [.control, .option], keyLabel: "V")

    @Test func anIconHasAtMostOneShortcut() {
        var shortcuts = Shortcuts()
        shortcuts.setShortcut(keyD, for: drive)
        shortcuts.setShortcut(keyV, for: drive)
        #expect(shortcuts.icons.count == 1)
        #expect(shortcuts.shortcut(for: drive) == keyV)
        shortcuts.setShortcut(nil, for: drive)
        #expect(shortcuts.icons.isEmpty)
        #expect(shortcuts.shortcut(for: drive) == nil)
    }

    @Test func iconShortcutsSurviveARoundTrip() throws {
        var shortcuts = Shortcuts(showEverything: keyV)
        shortcuts.setShortcut(keyD, for: drive)
        shortcuts.setShortcut(keyV, for: vpn)
        let decoded = try JSONDecoder().decode(Shortcuts.self, from: JSONEncoder().encode(shortcuts))
        #expect(decoded == shortcuts)
        #expect(decoded.showEverything == keyV)
    }

    @Test func aBrokenEntryCostsThatEntryOnly() throws {
        let json = #"""
        {"icons": [
          {"icon": {"bundleID": "com.google.drivefs", "key": ""}, "shortcut": {"keyCode": 2, "modifiers": 3, "keyLabel": "D"}},
          {"icon": 42},
          null,
          {"icon": {"bundleID": "com.google.drivefs", "key": ""}, "shortcut": {"keyCode": 9, "modifiers": 3, "keyLabel": "V"}}
        ]}
        """#
        let shortcuts = try JSONDecoder().decode(Shortcuts.self, from: Data(json.utf8))
        #expect(shortcuts.icons.count == 1)
        #expect(shortcuts.icons.first?.shortcut.keyLabel == "D", "the first shortcut for an icon wins")
        #expect(shortcuts.search == .defaultSearch)
        #expect(shortcuts.showEverything == nil)
    }
}

@Suite struct SettingsFileTests {
    @Test func anExportReadsBackIdentically() throws {
        var settings = TiroirSettings.defaults
        settings.layout.addDrawer(Drawer(name: "Files & Cloud", mark: .symbol("cloud.fill"), category: .files))
        settings.behavior.revealsOnClick = true
        settings.shortcuts.setShortcut(Shortcut(keyCode: 2, modifiers: [.control, .option], keyLabel: "D"),
                                       for: IconID(bundleID: "com.google.drivefs"))
        settings.hasCompletedWelcome = true
        let data = try #require(SettingsStore.data(settings, pretty: true))
        #expect(String(decoding: data, as: UTF8.self).contains("\n"), "an exported file is readable")
        #expect(try SettingsStore.read(data).get() == settings)
    }

    @Test func aFileFromANewerTiroirIsRefused() {
        let data = Data(#"{"schemaVersion": 9, "layout": {}}"#.utf8)
        #expect(SettingsStore.read(data) == .failure(.newerVersion(9)))
    }

    @Test func somethingElseIsRefused() {
        #expect(SettingsStore.read(Data("[1, 2]".utf8)) == .failure(.unreadable))
        #expect(SettingsStore.read(Data("hello".utf8)) == .failure(.unreadable))
    }

    @Test func valuesOutOfRangeAreClampedOnImport() throws {
        let data = Data(#"{"schemaVersion": 1, "behavior": {"hideAgainDelay": 999}}"#.utf8)
        #expect(try SettingsStore.read(data).get().behavior.hideAgainDelay == 30)
    }
}

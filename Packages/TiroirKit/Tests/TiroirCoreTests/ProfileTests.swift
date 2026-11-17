import Foundation
import Testing
@testable import TiroirCore

@Suite struct ProfileTests {
    let cloud = Drawer(name: "Files & Cloud", mark: .symbol("cloud.fill"), category: .files)
    let chat = Drawer(name: "Messages", mark: .symbol("bubble.left.fill"), category: .messages)
    let drive = IconID(bundleID: "com.google.drivefs")
    let slack = IconID(bundleID: "com.tinyspeck.slackmacgap")
    let ids = SequentialIDs()

    /// A menu bar with one drawer, Google Drive in it, and a honey tint.
    func setup() -> TiroirSettings {
        var settings = TiroirSettings(hasCompletedWelcome: true)
        settings.layout.addDrawer(cloud)
        settings.layout.assign(drive, to: .drawer(cloud.id))
        settings.appearance.tint = .color
        return settings
    }

    @Test func withoutProfilesNothingChanges() {
        var settings = setup()
        let before = settings
        settings.writeThrough()
        settings.switchProfile(to: UUID())
        #expect(settings == before)
        #expect(settings.currentProfile == nil)
    }

    @Test func savingTheCurrentSetupMakesAnActiveProfile() {
        var settings = setup()
        let id = settings.saveCurrentAsProfile(named: "  Work  ", id: ids.make())
        #expect(settings.activeProfile == id)
        #expect(settings.profiles.count == 1)
        #expect(settings.currentProfile?.name == "Work")
        #expect(settings.currentProfile?.layout == settings.layout)
        #expect(settings.currentProfile?.appearance == settings.appearance)
    }

    @Test func theActiveProfileFollowsEveryChange() {
        var settings = setup()
        settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        settings.layout.assign(slack, to: .hidden)
        settings.appearance.border = true
        settings.writeThrough()
        #expect(settings.currentProfile?.layout.placements[slack] == .hidden)
        #expect(settings.currentProfile?.appearance.border == true)
    }

    @Test func switchingAwayAndBackFindsTheSetupAsItWasLeft() {
        var settings = setup()
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        let talk = settings.saveCurrentAsProfile(named: "Talk", id: ids.make())
        settings.layout.addDrawer(chat)
        settings.layout.assign(slack, to: .drawer(chat.id))
        settings.appearance.tint = .gradient
        settings.writeThrough()
        let talkSetup = (settings.layout, settings.appearance)

        settings.switchProfile(to: work)
        #expect(settings.activeProfile == work)
        #expect(settings.layout.drawers == [cloud])
        #expect(settings.appearance.tint == .color)
        // A change made while Work is active, never seen by Talk.
        settings.layout.assign(drive, to: .hidden)
        settings.writeThrough()

        settings.switchProfile(to: talk)
        #expect(settings.layout == talkSetup.0)
        #expect(settings.appearance == talkSetup.1)
        settings.switchProfile(to: work)
        #expect(settings.layout.placements[drive] == .hidden)
    }

    @Test func switchingWritesTheSetupBeingLeftFirst() {
        var settings = setup()
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        let talk = settings.saveCurrentAsProfile(named: "Talk", id: ids.make())
        // Changed without a write-through, as if settings came from an older Tiroir.
        settings.appearance.shadow = true
        settings.switchProfile(to: work)
        #expect(settings.profile(talk)?.appearance.shadow == true)
    }

    @Test func renamingCleansTheNameAndRefusesAnEmptyOne() {
        var settings = setup()
        let id = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        settings.renameProfile(id, to: "  Studio  ")
        #expect(settings.profile(id)?.name == "Studio")
        settings.renameProfile(id, to: "   ")
        #expect(settings.profile(id)?.name == "Studio")
        settings.renameProfile(id, to: String(repeating: "a", count: 90))
        #expect(settings.profile(id)?.name.count == Profile.maximumNameLength)
    }

    @Test func aDuplicateFollowsItsOriginalWithoutShortcutAndInactive() {
        var settings = setup()
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        let home = settings.saveCurrentAsProfile(named: "Home", id: ids.make())
        settings.setShortcut(.defaultFocus, ofProfile: work)
        let copy = settings.duplicateProfile(work, named: "Work Copy", as: ids.make())
        #expect(settings.profiles.map(\.name) == ["Work", "Work Copy", "Home"])
        #expect(settings.activeProfile == home)
        #expect(copy.flatMap(settings.profile)?.shortcut == nil)
        #expect(copy.flatMap(settings.profile)?.layout == settings.profile(work)?.layout)
        #expect(settings.duplicateProfile(UUID(), named: "Nothing") == nil)
    }

    @Test func deletingTheActiveProfileKeepsTheSetupAndLeavesNoneActive() {
        var settings = setup()
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        let before = (settings.layout, settings.appearance)
        settings.deleteProfile(work)
        #expect(settings.profiles.isEmpty)
        #expect(settings.activeProfile == nil)
        #expect(settings.layout == before.0)
        #expect(settings.appearance == before.1)
    }

    @Test func deletingAnotherProfileLeavesTheActiveOne() {
        var settings = setup()
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        let home = settings.saveCurrentAsProfile(named: "Home", id: ids.make())
        settings.deleteProfile(work)
        #expect(settings.activeProfile == home)
        #expect(settings.profiles.map(\.name) == ["Home"])
    }

    @Test func profilesMove() {
        var settings = setup()
        let a = settings.saveCurrentAsProfile(named: "A", id: ids.make())
        settings.saveCurrentAsProfile(named: "B", id: ids.make())
        let c = settings.saveCurrentAsProfile(named: "C", id: ids.make())
        settings.moveProfile(c, to: 0)
        #expect(settings.profiles.map(\.name) == ["C", "A", "B"])
        settings.moveProfile(a, to: 99)
        #expect(settings.profiles.map(\.name) == ["C", "B", "A"])
    }

    @Test func eachProfileHasItsOwnShortcut() {
        var settings = setup()
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        settings.setShortcut(.defaultSearch, ofProfile: work)
        #expect(settings.profile(work)?.shortcut == .defaultSearch)
        settings.setShortcut(nil, ofProfile: work)
        #expect(settings.profile(work)?.shortcut == nil)
    }

    @Test func newNamesSkipTheOnesTaken() {
        var settings = setup()
        let spell: (Int) -> String = { "Profile \($0)" }
        #expect(settings.nextProfileName(spell) == "Profile 1")
        settings.saveCurrentAsProfile(named: "Profile 2", id: ids.make())
        #expect(settings.nextProfileName(spell) == "Profile 3")
        settings.saveCurrentAsProfile(named: "Profile 3", id: ids.make())
        #expect(settings.nextProfileName(spell) == "Profile 4")
    }

    @Test func aSetupComesBackWithoutAProfile() {
        var settings = setup()
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        settings.restoreSetup(layout: .empty, appearance: .standard)
        #expect(settings.activeProfile == nil)
        #expect(settings.layout == .empty)
        #expect(settings.profile(work)?.layout.drawers == [cloud])
    }

    @Test func clampingDropsAnActiveProfileThatDoesNotExistAndDuplicates() {
        var settings = setup()
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        settings.profiles.append(Profile(id: work, name: "Twin", layout: .empty, appearance: .standard))
        settings.profiles.append(Profile(id: ids.make(), name: "  Padded  ", layout: .empty, appearance: .standard))
        #expect(settings.clamped.profiles.map(\.name) == ["Work", "Padded"])
        settings.activeProfile = UUID()
        #expect(settings.clamped.activeProfile == nil)
    }
}

@Suite struct ProfileCodingTests {
    let ids = SequentialIDs()

    @Test func profilesSurviveARoundTrip() throws {
        var settings = TiroirSettings(hasCompletedWelcome: true)
        settings.layout.addDrawer(Drawer(name: "Files", mark: .symbol("cloud.fill")))
        settings.appearance.tint = .gradient
        let id = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        settings.setShortcut(.defaultFocus, ofProfile: id)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(TiroirSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.schemaVersion == 1)
    }

    /// Settings saved before profiles and triggers existed load unchanged.
    @Test func olderSettingsLoadUnchanged() throws {
        var settings = TiroirSettings(hasCompletedWelcome: true)
        settings.layout.addDrawer(Drawer(name: "Files", mark: .symbol("cloud.fill")))
        settings.behavior.opensOnHover = true
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        for key in ["profiles", "activeProfile", "triggers", "triggerMemory"] { object[key] = nil }
        let decoded = try JSONDecoder().decode(TiroirSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == settings)
        #expect(decoded.profiles.isEmpty)
        #expect(decoded.activeProfile == nil)
        #expect(decoded.triggers.isEmpty)
        #expect(decoded.triggerMemory == .empty)
    }

    @Test func aProfileThatCannotBeReadIsSkippedNotTheSettings() throws {
        let good = "00000000-0000-0000-0000-000000000001"
        let json = """
        {"hasCompletedWelcome": true, "activeProfile": "\(good)", "profiles": [
          42,
          {"name": "No identity", "layout": {}},
          {"id": "00000000-0000-0000-0000-000000000002", "name": "No layout"},
          {"id": "\(good)", "name": "Work", "layout": {"drawers": []}, "appearance": "not an appearance", "future": 1}
        ]}
        """
        let settings = try JSONDecoder().decode(TiroirSettings.self, from: Data(json.utf8))
        #expect(settings.hasCompletedWelcome)
        #expect(settings.profiles.map(\.name) == ["Work"])
        #expect(settings.profiles.first?.appearance == .standard)
        #expect(settings.activeProfile == UUID(uuidString: good))
    }

    @Test func aProfilesValueOfTheWrongTypeGivesNoProfiles() throws {
        let settings = try JSONDecoder().decode(TiroirSettings.self, from: Data(#"{"profiles": "many", "activeProfile": 3}"#.utf8))
        #expect(settings.profiles.isEmpty)
        #expect(settings.activeProfile == nil)
    }

    @Test func theStoreDropsAnActiveProfileThatIsGone() {
        let name = scratchDefaultsName()
        let defaults = UserDefaults(suiteName: name)!
        defer { discardDefaults(name) }
        let json = #"{"schemaVersion": 1, "activeProfile": "00000000-0000-0000-0000-000000000009", "profiles": []}"#
        defaults.set(Data(json.utf8), forKey: "settings")
        let (settings, outcome) = SettingsStore(defaults: defaults).load()
        #expect(outcome == .loaded)
        #expect(settings.activeProfile == nil)
    }
}

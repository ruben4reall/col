import AppKit
import Foundation
import Testing
import TiroirCore
@testable import TiroirUI

/// A row for an icon Tiroir sees, with a plain picture.
@MainActor
func row(_ id: IconID, name: String, category: CategoryID = .other, kind: IconKind = .app, movable: Bool = true) -> IconRow {
    IconRow(id: id, name: name, appName: name, appIcon: NSImage(), category: category, developer: "Example", kind: kind, isMovable: movable)
}

@MainActor
@Suite struct ProfileInterfaceTests {
    @Test func everyChangeIsWrittenIntoTheActiveProfile() {
        let model = InterfaceModel(settings: TiroirSettings(hasCompletedWelcome: true))
        var saved: [TiroirSettings] = []
        model.actions.updateSettings = { saved.append($0) }
        let id = model.saveCurrentAsProfile(named: "Work")
        model.update { $0.appearance.border = true }
        model.move(IconID(bundleID: "com.example.cloud"), to: .hidden)
        #expect(model.settings.activeProfile == id)
        #expect(model.settings.profile(id)?.appearance.border == true)
        #expect(model.settings.profile(id)?.layout.placements[IconID(bundleID: "com.example.cloud")] == .hidden)
        #expect(saved.last == model.settings)
    }

    @Test func withoutProfilesAnUpdateChangesOnlyWhatItSays() {
        let model = InterfaceModel(settings: TiroirSettings(hasCompletedWelcome: true))
        model.update { $0.appearance.shadow = true }
        #expect(model.settings.profiles.isEmpty)
        #expect(model.settings.appearance.shadow)
    }

    @Test func switchingByHandGoesThroughTheApp() {
        let model = InterfaceModel(settings: TiroirSettings(hasCompletedWelcome: true))
        let id = model.saveCurrentAsProfile(named: "Work")
        var asked: [UUID] = []
        model.actions.switchProfile = { asked.append($0) }
        model.switchProfile(to: id)
        #expect(asked == [id])
    }

    @Test func profileWordsFillIn() {
        #expect(Strings.drawerCount(1) == "1 drawer")
        #expect(Strings.drawerCount(4) == "4 drawers")
        #expect(Strings.numberedProfileName(2) == "Profile 2")
        #expect(Strings.copyName("Work") == "Work Copy")
        #expect(Strings.deleteProfileQuestion("Work").contains("“Work”"))
        #expect(Strings.name(of: Profile(name: "", layout: .empty, appearance: .standard)) == Strings.untitledProfile)
    }
}

@MainActor
@Suite struct TriggerDraftTests {
    let chat = Drawer(name: "Messages", mark: .symbol("bubble.left.fill"), category: .messages)

    func settings() -> TiroirSettings {
        var settings = TiroirSettings(hasCompletedWelcome: true)
        settings.layout.addDrawer(chat)
        settings.saveCurrentAsProfile(named: "Work")
        return settings
    }

    @Test func aNewDraftNeedsAnApp() {
        var draft = TriggerDraft(in: settings())
        #expect(draft.isNew)
        #expect(draft.condition == .appOpen)
        #expect(draft.action == .showDrawer)
        #expect(draft.trigger == nil)
        draft.app = "us.zoom.xos"
        #expect(draft.trigger?.condition == .appOpen("us.zoom.xos"))
        #expect(draft.trigger?.action == .showDrawer(chat.id))
    }

    @Test func withoutDrawersOrProfilesANewDraftFocuses() {
        let draft = TriggerDraft(in: TiroirSettings())
        #expect(draft.action == .focus)
    }

    @Test func aTimeRangeNeedsTwoDifferentTimes() {
        var draft = TriggerDraft(in: settings())
        draft.condition = .timeOfDay
        draft.from = 600
        draft.to = 600
        #expect(draft.trigger == nil)
        draft.to = 480
        #expect(draft.trigger?.condition == .timeOfDay(from: 600, to: 480))
    }

    @Test func everyTriggerComesBackFromItsDraft() {
        let settings = settings()
        let work = settings.profiles[0].id
        let triggers = [
            Trigger(condition: .appInFront("com.apple.iWork.Keynote"), action: .focus),
            Trigger(isEnabled: false, condition: .batteryAtOrBelow(15), action: .showIcon(IconID(bundleID: "com.example.stats"))),
            Trigger(condition: .timeOfDay(from: 1320, to: 420), action: .switchProfile(work)),
            Trigger(condition: .cameraOrMicrophone, action: .showDrawer(chat.id)),
            Trigger(condition: .onBattery, action: .focus),
            Trigger(condition: .externalDisplay, action: .focus),
        ]
        for trigger in triggers {
            let draft = TriggerDraft(editing: trigger, in: settings)
            #expect(!draft.isNew)
            #expect(draft.trigger == trigger)
        }
    }

    @Test func aProfileThatIsGoneIsLeftUnchosen() {
        let draft = TriggerDraft(editing: Trigger(condition: .onBattery, action: .switchProfile(UUID())), in: settings())
        #expect(draft.profile == nil)
        #expect(draft.trigger == nil)
    }

    @Test func savingReplacesByIdentityAndRemovingForgets() {
        let model = InterfaceModel(settings: settings())
        var trigger = Trigger(condition: .onBattery, action: .focus)
        model.saveTrigger(trigger)
        trigger.isEnabled = false
        model.saveTrigger(trigger)
        #expect(model.settings.triggers == [trigger])
        model.saveTrigger(Trigger(condition: .batteryAtOrBelow(500), action: .focus))
        #expect(model.settings.triggers.last?.condition == .batteryAtOrBelow(100), "kept inside its range")
        model.removeTrigger(trigger.id)
        #expect(model.settings.triggers.count == 1)
    }
}

@MainActor
@Suite struct TriggerTextTests {
    let chat = Drawer(name: "Messages", mark: .symbol("bubble.left.fill"), category: .messages)
    let tools = Drawer(name: "Tools", mark: .symbol("hammer.fill"), category: .developer)
    let battery = IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.battery")

    func model(drawers: [Drawer] = [], rows: [IconRow] = []) -> InterfaceModel {
        var settings = TiroirSettings(hasCompletedWelcome: true)
        for drawer in drawers { settings.layout.addDrawer(drawer) }
        let model = InterfaceModel(settings: settings)
        model.icons = rows
        return model
    }

    @Test func triggersReadAsSentences() {
        let model = model(drawers: [chat], rows: [row(battery, name: "Battery", kind: .system)])
        let camera = Trigger(condition: .cameraOrMicrophone, action: .showDrawer(chat.id))
        #expect(TriggerText.sentence(camera, in: model)
            == "When the camera or the microphone is in use, show the Messages drawer in the menu bar")
        let low = Trigger(condition: .batteryAtOrBelow(20), action: .showIcon(battery))
        #expect(TriggerText.sentence(low, in: model)
            == "When the battery is at or below \(Strings.percent(20)), show Battery in the menu bar")
        #expect(TriggerText.sentence(Trigger(condition: .onBattery, action: .focus), in: model)
            == "When the Mac runs on battery, turn on Focus")
        #expect(TriggerText.condition(.appOpen("com.example.chatapp")) == "chatapp is open", "an app that is not installed")
        #expect(TriggerText.condition(.timeOfDay(from: 1320, to: 420))
            == "it is between \(Strings.time(ofMinutes: 1320)) and \(Strings.time(ofMinutes: 420))")
    }

    @Test func aProfileTriggerNamesItsProfile() {
        let model = model()
        let id = model.saveCurrentAsProfile(named: "Talk")
        #expect(TriggerText.action(.switchProfile(id), in: model) == "switch to the Talk profile")
        #expect(TriggerText.problem(Trigger(condition: .onBattery, action: .switchProfile(id)), in: model) == nil)
    }

    @Test func whatNoLongerExistsIsSaid() {
        let model = model()
        let gone = Trigger(condition: .onBattery, action: .switchProfile(UUID()))
        #expect(TriggerText.action(gone.action, in: model) == Strings.switchToADeletedProfile)
        #expect(TriggerText.problem(gone, in: model) == Strings.profileIsGone)
        let drawer = Trigger(condition: .onBattery, action: .showDrawer(UUID()))
        #expect(TriggerText.action(drawer.action, in: model) == Strings.showADeletedDrawer)
        #expect(TriggerText.problem(drawer, in: model) == Strings.drawerIsGone)
    }

    /// A drawer kept by another profile only is named, and said to be out of the current setup.
    @Test func aDrawerOfAnotherProfileIsNamed() {
        let model = model(drawers: [chat])
        model.saveCurrentAsProfile(named: "Work")
        model.saveCurrentAsProfile(named: "Bare")
        model.removeDrawer(chat.id)
        let trigger = Trigger(condition: .onBattery, action: .showDrawer(chat.id))
        #expect(TriggerText.action(trigger.action, in: model) == "show the Messages drawer in the menu bar")
        #expect(TriggerText.problem(trigger, in: model) == Strings.drawerIsGone)
    }

    @Test func examplesFitThisMac() {
        let bare = TriggerExample.examples(in: model())
        #expect(bare.map(\.id) == ["keynote"])
        #expect(bare.first?.trigger.condition == .appInFront("com.apple.iWork.Keynote"))
        #expect(bare.first?.trigger.action == .focus)

        let full = TriggerExample.examples(in: model(drawers: [tools, chat], rows: [row(battery, name: "Battery", kind: .system)]))
        #expect(full.map(\.id) == ["battery", "chat", "keynote"])
        #expect(full[0].trigger.condition == .batteryAtOrBelow(20))
        #expect(full[0].trigger.action == .showIcon(battery))
        #expect(full[1].title == Strings.exampleChatDrawer)
        #expect(full[1].trigger.action == .showDrawer(chat.id))

        let other = TriggerExample.examples(in: model(drawers: [tools]))
        #expect(other.map(\.id) == ["chat", "keynote"])
        #expect(other[0].title == Strings.exampleDrawer("Tools"))
        #expect(other[0].trigger.action == .showDrawer(tools.id))
    }

    @Test func triggerWordsFillIn() {
        #expect(Strings.triggerSentence(when: "Zoom is open", then: "show the Messages drawer in the menu bar")
            == "When Zoom is open, show the Messages drawer in the menu bar")
        #expect(Strings.exampleBattery(level: "20%") == "Show Battery when it drops below 20%")
        #expect(Strings.nameWithLabel("iStat Menus", "CPU") == "iStat Menus, CPU")
        #expect(Strings.percent(20).contains("20"))
        #expect(Strings.conditionName(.cameraOrMicrophone) == "The camera or the microphone is in use")
        #expect(Strings.actionName(.showDrawer) == "Show a drawer's icons in the menu bar")
    }

    @Test func thePanesComeInTheirOrder() {
        #expect(SettingsPane.allCases == [.layout, .drawers, .profiles, .triggers, .appearance, .behavior, .shortcuts, .general, .about])
        let view = SettingsView(model: InterfaceModel())
        #expect(view.title(.profiles) == "Profiles")
        #expect(view.title(.triggers) == "Triggers")
        #expect(view.symbol(.profiles) == "square.stack.3d.up")
        #expect(view.symbol(.triggers) == "bolt")
        #expect(NSImage(systemSymbolName: view.symbol(.profiles), accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: view.symbol(.triggers), accessibilityDescription: nil) != nil)
    }
}

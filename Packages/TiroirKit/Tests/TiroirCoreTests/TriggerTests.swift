import Foundation
import Testing
@testable import TiroirCore

/// Minutes since midnight, for readable times.
func at(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

@Suite struct TriggerConditionTests {
    @Test func appsOpenAndInFront() {
        let facts = TriggerFacts(runningApps: ["us.zoom.xos", "com.apple.Safari"], frontmostApp: "com.apple.Safari")
        #expect(TriggerCondition.appOpen("us.zoom.xos").holds(in: facts))
        #expect(!TriggerCondition.appOpen("com.apple.iWork.Keynote").holds(in: facts))
        #expect(TriggerCondition.appInFront("com.apple.Safari").holds(in: facts))
        #expect(!TriggerCondition.appInFront("us.zoom.xos").holds(in: facts))
    }

    @Test func powerAndBattery() {
        #expect(TriggerCondition.onBattery.holds(in: TriggerFacts(isOnBattery: true)))
        #expect(!TriggerCondition.onBattery.holds(in: TriggerFacts(isOnBattery: false)))
        #expect(TriggerCondition.batteryAtOrBelow(20).holds(in: TriggerFacts(batteryPercent: 20)))
        #expect(TriggerCondition.batteryAtOrBelow(20).holds(in: TriggerFacts(batteryPercent: 7)))
        #expect(!TriggerCondition.batteryAtOrBelow(20).holds(in: TriggerFacts(batteryPercent: 21)))
        #expect(!TriggerCondition.batteryAtOrBelow(20).holds(in: TriggerFacts(batteryPercent: nil)), "a Mac without a battery")
    }

    @Test func displaysAndDevices() {
        #expect(TriggerCondition.externalDisplay.holds(in: TriggerFacts(hasExternalDisplay: true)))
        #expect(!TriggerCondition.externalDisplay.holds(in: TriggerFacts()))
        #expect(TriggerCondition.cameraOrMicrophone.holds(in: TriggerFacts(isCameraOrMicrophoneInUse: true)))
        #expect(!TriggerCondition.cameraOrMicrophone.holds(in: TriggerFacts()))
    }

    @Test func aTimeRangeIncludesItsStartNotItsEnd() {
        let office = TriggerCondition.timeOfDay(from: at(9), to: at(17))
        #expect(!office.holds(in: TriggerFacts(minutesSinceMidnight: at(8, 59))))
        #expect(office.holds(in: TriggerFacts(minutesSinceMidnight: at(9))))
        #expect(office.holds(in: TriggerFacts(minutesSinceMidnight: at(16, 59))))
        #expect(!office.holds(in: TriggerFacts(minutesSinceMidnight: at(17))))
    }

    @Test func aTimeRangeCanCrossMidnight() {
        let night = TriggerCondition.timeOfDay(from: at(22), to: at(6, 30))
        #expect(!night.holds(in: TriggerFacts(minutesSinceMidnight: at(21, 59))))
        #expect(night.holds(in: TriggerFacts(minutesSinceMidnight: at(22))))
        #expect(night.holds(in: TriggerFacts(minutesSinceMidnight: at(23, 59))))
        #expect(night.holds(in: TriggerFacts(minutesSinceMidnight: 0)))
        #expect(night.holds(in: TriggerFacts(minutesSinceMidnight: at(6, 29))))
        #expect(!night.holds(in: TriggerFacts(minutesSinceMidnight: at(6, 30))))
        #expect(!night.holds(in: TriggerFacts(minutesSinceMidnight: at(12))))
    }

    @Test func aRangeThatEndsWhereItStartsNeverHolds() {
        let empty = TriggerCondition.timeOfDay(from: at(9), to: at(9))
        #expect(!empty.holds(in: TriggerFacts(minutesSinceMidnight: at(9))))
        #expect(!empty.holds(in: TriggerFacts(minutesSinceMidnight: at(3))))
    }

    @Test func valuesAreBroughtInsideTheirRanges() {
        #expect(TriggerCondition.batteryAtOrBelow(0).clamped == .batteryAtOrBelow(1))
        #expect(TriggerCondition.batteryAtOrBelow(150).clamped == .batteryAtOrBelow(100))
        #expect(TriggerCondition.timeOfDay(from: -5, to: 5000).clamped == .timeOfDay(from: 0, to: 1439))
    }
}

@Suite struct TriggerCodingTests {
    let profile = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let drawer = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test func everyKindSurvivesARoundTrip() throws {
        let conditions: [TriggerCondition] = [
            .appOpen("us.zoom.xos"), .appInFront("com.apple.iWork.Keynote"), .onBattery, .batteryAtOrBelow(20),
            .externalDisplay, .timeOfDay(from: at(22), to: at(7)), .cameraOrMicrophone,
        ]
        let actions: [TriggerAction] = [
            .switchProfile(profile), .showDrawer(drawer),
            .showIcon(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.battery")), .focus,
        ]
        #expect(conditions.map(\.kind) == TriggerCondition.Kind.allCases)
        #expect(actions.map(\.kind) == TriggerAction.Kind.allCases)
        for condition in conditions {
            for action in actions {
                let trigger = Trigger(isEnabled: false, condition: condition, action: action)
                #expect(try JSONDecoder().decode(Trigger.self, from: JSONEncoder().encode(trigger)) == trigger)
            }
        }
    }

    @Test func theEncodingIsReadable() throws {
        let data = try JSONEncoder().encode(TriggerCondition.appOpen("us.zoom.xos"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["kind": "appOpen", "app": "us.zoom.xos"])
    }

    /// A newer Tiroir may know kinds this one does not: those triggers are skipped, the others and the settings stay.
    @Test func unknownKindsAreSkippedNeverACrash() throws {
        let json = """
        {"hasCompletedWelcome": true, "triggers": [
          {"id": "00000000-0000-0000-0000-000000000001", "condition": {"kind": "wifiNetwork", "name": "Home"}, "action": {"kind": "focus"}},
          {"id": "00000000-0000-0000-0000-000000000002", "condition": {"kind": "onBattery"}, "action": {"kind": "playSound"}},
          {"id": "00000000-0000-0000-0000-000000000003", "condition": {"kind": "appOpen"}, "action": {"kind": "focus"}},
          {"id": "00000000-0000-0000-0000-000000000004", "condition": {"kind": "onBattery"}, "action": {"kind": "focus"}},
          "nonsense",
          {"condition": {"kind": "externalDisplay"}, "action": {"kind": "showDrawer", "drawer": "\(drawer)"}}
        ]}
        """
        let settings = try JSONDecoder().decode(TiroirSettings.self, from: Data(json.utf8))
        #expect(settings.hasCompletedWelcome)
        #expect(settings.triggers.map(\.condition) == [.onBattery, .externalDisplay])
        #expect(settings.triggers.allSatisfy { $0.isEnabled }, "a trigger without the key is on")
        #expect(settings.triggers.first?.id == UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
    }

    @Test func theMemorySurvivesARoundTripAndAnUnreadableOneIsEmpty() throws {
        let memory = TriggerMemory(
            hold: ProfileHold(trigger: drawer, profile: profile, previous: .setup(Layout(newIconPolicy: .hidden), Appearance(border: true))),
            overruled: [drawer])
        #expect(try JSONDecoder().decode(TriggerMemory.self, from: JSONEncoder().encode(memory)) == memory)
        let other = TriggerMemory(hold: ProfileHold(trigger: drawer, profile: profile, previous: .profile(drawer)))
        #expect(try JSONDecoder().decode(TriggerMemory.self, from: JSONEncoder().encode(other)) == other)
        let settings = try JSONDecoder().decode(TiroirSettings.self, from: Data(#"{"triggerMemory": {"hold": 3, "overruled": "x"}}"#.utf8))
        #expect(settings.triggerMemory == .empty)
    }
}

@Suite struct TriggerEvaluatorTests {
    let ids = SequentialIDs()
    let zoom = "us.zoom.xos"
    let keynote = "com.apple.iWork.Keynote"
    let battery = IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.battery")
    let chat = Drawer(name: "Messages", mark: .symbol("bubble.left.fill"), category: .messages)

    /// Two profiles with a Messages drawer: Talk without a tint, Work, active, with one; and the given triggers.
    func makeSettings(_ triggers: [Trigger] = []) -> (settings: TiroirSettings, work: UUID, talk: UUID) {
        var settings = TiroirSettings(hasCompletedWelcome: true)
        settings.layout.addDrawer(chat)
        let talk = settings.saveCurrentAsProfile(named: "Talk", id: ids.make())
        let work = settings.saveCurrentAsProfile(named: "Work", id: ids.make())
        settings.appearance.tint = .color
        settings.writeThrough()
        settings.triggers = triggers
        return (settings, work, talk)
    }

    /// Evaluates, applies the outcome the way the coordinator does, and returns it.
    @discardableResult
    func step(_ settings: inout TiroirSettings, _ facts: TriggerFacts, _ state: inout TriggerState, suspended: Bool = false) -> TriggerOutcome {
        let outcome = TriggerEvaluator.evaluate(settings, facts: facts, state: state, isSuspended: suspended)
        state = outcome.state
        settings.apply(outcome)
        return outcome
    }

    @Test func withoutTriggersNothingHappens() {
        let outcome = TriggerEvaluator.evaluate(makeSettings().settings, facts: TriggerFacts(runningApps: [zoom], isOnBattery: true))
        #expect(outcome.active.isEmpty)
        #expect(outcome.effect == .none)
        #expect(outcome.profileChange == nil)
    }

    @Test func showActionsAddUp() {
        let triggers = [
            Trigger(condition: .appOpen(zoom), action: .showDrawer(chat.id)),
            Trigger(condition: .batteryAtOrBelow(20), action: .showIcon(battery)),
            Trigger(condition: .onBattery, action: .showIcon(IconID(bundleID: "com.example.stats"))),
        ]
        let outcome = TriggerEvaluator.evaluate(makeSettings(triggers).settings,
                                                facts: TriggerFacts(runningApps: [zoom], isOnBattery: true, batteryPercent: 12))
        #expect(outcome.active == Set(triggers.map(\.id)))
        #expect(outcome.effect.drawers == [chat.id])
        #expect(outcome.effect.icons == [battery, IconID(bundleID: "com.example.stats")])
        #expect(!outcome.effect.focus)
    }

    @Test func focusWinsOverShownIcons() {
        let triggers = [
            Trigger(condition: .appInFront(keynote), action: .focus),
            Trigger(condition: .appInFront(keynote), action: .showIcon(battery)),
        ]
        let outcome = TriggerEvaluator.evaluate(makeSettings(triggers).settings, facts: TriggerFacts(frontmostApp: keynote))
        #expect(outcome.effect.focus)
        let planning = outcome.effect.planning(over: .normal)
        #expect(planning.mode == .focus)
        #expect(planning.icons.isEmpty && planning.drawers.isEmpty)
    }

    @Test func thePersonsFocusOrShowEverythingWinsOverTriggers() {
        let effect = TriggerEffect(focus: true, icons: [battery], drawers: [chat.id])
        #expect(effect.planning(over: .showEverything) == TriggerEffect.Planning(mode: .showEverything, icons: [], drawers: []))
        #expect(effect.planning(over: .focus).mode == .focus)
        let shows = TriggerEffect(icons: [battery], drawers: [chat.id])
        #expect(shows.planning(over: .normal) == TriggerEffect.Planning(mode: .normal, icons: [battery], drawers: [chat.id]))
        #expect(TriggerEffect.none.planning(over: .normal).mode == .normal)
    }

    @Test func disabledAndDanglingTriggersDoNothing() {
        var (settings, _, _) = makeSettings()
        settings.triggers = [
            Trigger(isEnabled: false, condition: .onBattery, action: .focus),
            Trigger(condition: .onBattery, action: .switchProfile(UUID())),
            Trigger(condition: .onBattery, action: .showDrawer(UUID())),
        ]
        let outcome = TriggerEvaluator.evaluate(settings, facts: TriggerFacts(isOnBattery: true))
        #expect(outcome.active.isEmpty)
        #expect(outcome.effect == .none)
        #expect(outcome.profileChange == nil)
        #expect(outcome.memory == .empty)
    }

    /// Showing the icon of an app that does not run is harmless: the trigger counts as active.
    @Test func anIconNeedNotBeInTheMenuBar() {
        let trigger = Trigger(condition: .onBattery, action: .showIcon(IconID(bundleID: "com.example.gone")))
        let outcome = TriggerEvaluator.evaluate(makeSettings([trigger]).settings, facts: TriggerFacts(isOnBattery: true))
        #expect(outcome.active == [trigger.id])
    }

    @Test func whileSuspendedTriggersChangeNothingButStillCount() {
        var (settings, _, talk) = makeSettings()
        let focus = Trigger(condition: .appInFront(keynote), action: .focus)
        let profile = Trigger(condition: .appInFront(keynote), action: .switchProfile(talk))
        settings.triggers = [focus, profile]
        let outcome = TriggerEvaluator.evaluate(settings, facts: TriggerFacts(frontmostApp: keynote), isSuspended: true)
        #expect(outcome.active == [focus.id, profile.id])
        #expect(outcome.effect == .none)
        #expect(outcome.profileChange == nil)
        #expect(outcome.memory.hold == nil)
    }

    @Test func aProfileComesWithTheConditionAndGoesWithIt() {
        var (settings, work, talk) = makeSettings()
        settings.triggers = [Trigger(condition: .appInFront(keynote), action: .switchProfile(talk))]
        var state = TriggerState()
        let started = step(&settings, TriggerFacts(frontmostApp: keynote), &state)
        #expect(started.profileChange == .switchTo(talk))
        #expect(settings.activeProfile == talk)
        #expect(settings.appearance.tint == .none, "Talk's own appearance")
        let ended = step(&settings, TriggerFacts(frontmostApp: "com.apple.finder"), &state)
        #expect(ended.profileChange == .restore(.profile(work)))
        #expect(settings.activeProfile == work)
        #expect(settings.appearance.tint == .color)
        #expect(settings.triggerMemory == .empty)
    }

    @Test func changesMadeUnderATriggersProfileStayInIt() {
        var (settings, work, talk) = makeSettings()
        settings.triggers = [Trigger(condition: .onBattery, action: .switchProfile(talk))]
        var state = TriggerState()
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        settings.appearance.shadow = true
        settings.writeThrough()
        step(&settings, TriggerFacts(isOnBattery: false), &state)
        #expect(settings.activeProfile == work)
        #expect(!settings.appearance.shadow)
        #expect(settings.profile(talk)?.appearance.shadow == true)
    }

    @Test func theTriggerThatStartedLastWinsThenTheOtherComesBack() {
        var (settings, work, talk) = makeSettings()
        let travel = settings.saveCurrentAsProfile(named: "Travel", id: ids.make())
        settings.switchProfile(to: work)
        settings.triggers = [
            Trigger(condition: .onBattery, action: .switchProfile(travel)),
            Trigger(condition: .appInFront(keynote), action: .switchProfile(talk)),
        ]
        var state = TriggerState()
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        #expect(settings.activeProfile == travel)
        step(&settings, TriggerFacts(frontmostApp: keynote, isOnBattery: true), &state)
        #expect(settings.activeProfile == talk, "Keynote came in front after the battery")
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        #expect(settings.activeProfile == travel)
        step(&settings, TriggerFacts(), &state)
        #expect(settings.activeProfile == work, "what was there before the first trigger")
    }

    @Test func triggersStartingTogetherFollowTheListTheLastOneWinning() {
        var (settings, work, talk) = makeSettings()
        let travel = settings.saveCurrentAsProfile(named: "Travel", id: ids.make())
        settings.switchProfile(to: work)
        settings.triggers = [
            Trigger(condition: .onBattery, action: .switchProfile(talk)),
            Trigger(condition: .externalDisplay, action: .switchProfile(travel)),
        ]
        var state = TriggerState()
        step(&settings, TriggerFacts(isOnBattery: true, hasExternalDisplay: true), &state)
        #expect(settings.activeProfile == travel)
    }

    @Test func aProfileSwitchedByHandStays() {
        var (settings, work, talk) = makeSettings()
        let travel = settings.saveCurrentAsProfile(named: "Travel", id: ids.make())
        settings.switchProfile(to: work)
        let trigger = Trigger(condition: .appInFront(keynote), action: .switchProfile(talk))
        settings.triggers = [trigger]
        var state = TriggerState()
        let inFront = TriggerFacts(frontmostApp: keynote)
        step(&settings, inFront, &state)
        #expect(settings.activeProfile == talk)

        settings.switchProfile(to: travel)
        let noticed = step(&settings, inFront, &state)
        #expect(noticed.profileChange == nil, "the trigger does not take it back while it holds")
        #expect(settings.activeProfile == travel)
        #expect(settings.triggerMemory.overruled == [trigger.id])

        let ended = step(&settings, TriggerFacts(), &state)
        #expect(ended.profileChange == nil, "nothing comes back over the person's choice")
        #expect(settings.activeProfile == travel)
        #expect(settings.triggerMemory == .empty)

        step(&settings, inFront, &state)
        #expect(settings.activeProfile == talk, "the next time the condition starts, the trigger acts again")
        step(&settings, TriggerFacts(), &state)
        #expect(settings.activeProfile == travel)
    }

    @Test func aTriggerStartingAfterAHandSwitchStillActs() {
        var (settings, _, talk) = makeSettings()
        let travel = settings.saveCurrentAsProfile(named: "Travel", id: ids.make())
        settings.triggers = [
            Trigger(condition: .onBattery, action: .switchProfile(talk)),
            Trigger(condition: .appInFront(keynote), action: .switchProfile(travel)),
        ]
        var state = TriggerState()
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        #expect(settings.activeProfile == talk)
        let home = settings.saveCurrentAsProfile(named: "Home", id: ids.make())
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        #expect(settings.activeProfile == home)
        step(&settings, TriggerFacts(frontmostApp: keynote, isOnBattery: true), &state)
        #expect(settings.activeProfile == travel)
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        #expect(settings.activeProfile == home, "the battery trigger was overruled: Home, chosen by hand, comes back")
    }

    @Test func withoutAnActiveProfileTheSetupOfThatMomentComesBack() {
        var (settings, work, talk) = makeSettings()
        settings.deleteProfile(work)
        settings.layout.assign(IconID(bundleID: "com.example.stats"), to: .hidden)
        let before = (settings.layout, settings.appearance)
        settings.triggers = [Trigger(condition: .externalDisplay, action: .switchProfile(talk))]
        var state = TriggerState()
        step(&settings, TriggerFacts(hasExternalDisplay: true), &state)
        #expect(settings.activeProfile == talk)
        let ended = step(&settings, TriggerFacts(), &state)
        #expect(ended.profileChange == .restore(.setup(before.0, before.1)))
        #expect(settings.activeProfile == nil)
        #expect(settings.layout == before.0)
        #expect(settings.appearance == before.1)
    }

    @Test func aRestartInTheMiddleKeepsThePromise() {
        var (settings, work, talk) = makeSettings()
        settings.triggers = [Trigger(condition: .onBattery, action: .switchProfile(talk))]
        var state = TriggerState()
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        let saved = settings

        // Relaunched while still on battery: nothing moves.
        var relaunched = saved
        var fresh = TriggerState()
        let again = step(&relaunched, TriggerFacts(isOnBattery: true), &fresh)
        #expect(again.profileChange == nil)
        #expect(relaunched.activeProfile == talk)
        step(&relaunched, TriggerFacts(), &fresh)
        #expect(relaunched.activeProfile == work)

        // Relaunched once plugged in: Work comes back at once.
        var plugged = saved
        var other = TriggerState()
        step(&plugged, TriggerFacts(), &other)
        #expect(plugged.activeProfile == work)
    }

    @Test func afterARestartTheTriggerInPlaceStaysAheadOfOthers() {
        var (settings, _, talk) = makeSettings()
        let travel = settings.saveCurrentAsProfile(named: "Travel", id: ids.make())
        let battery = Trigger(condition: .onBattery, action: .switchProfile(talk))
        let display = Trigger(condition: .externalDisplay, action: .switchProfile(travel))
        settings.triggers = [battery, display]
        var state = TriggerState()
        step(&settings, TriggerFacts(hasExternalDisplay: true), &state)
        step(&settings, TriggerFacts(isOnBattery: true, hasExternalDisplay: true), &state)
        #expect(settings.activeProfile == talk)
        var fresh = TriggerState()
        let relaunch = step(&settings, TriggerFacts(isOnBattery: true, hasExternalDisplay: true), &fresh)
        #expect(relaunch.profileChange == nil)
        #expect(settings.activeProfile == talk)
    }

    @Test func turningOffTheTriggerInPlaceBringsThePreviousProfileBack() {
        var (settings, work, talk) = makeSettings()
        var trigger = Trigger(condition: .onBattery, action: .switchProfile(talk))
        settings.triggers = [trigger]
        var state = TriggerState()
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        trigger.isEnabled = false
        settings.triggers = [trigger]
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        #expect(settings.activeProfile == work)
    }

    @Test func deletingTheProfileInPlaceLeavesTheSetupAlone() {
        var (settings, _, talk) = makeSettings()
        settings.triggers = [Trigger(condition: .onBattery, action: .switchProfile(talk))]
        var state = TriggerState()
        step(&settings, TriggerFacts(isOnBattery: true), &state)
        settings.deleteProfile(talk)
        let layout = settings.layout
        let outcome = step(&settings, TriggerFacts(isOnBattery: true), &state)
        #expect(outcome.profileChange == nil)
        #expect(outcome.active.isEmpty)
        #expect(settings.activeProfile == nil)
        #expect(settings.layout == layout)
        #expect(settings.triggerMemory.hold == nil)
    }

    @Test func aProfileThatEndedDuringTheFocusOfThePersonComesBackAfterIt() {
        var (settings, work, talk) = makeSettings()
        settings.triggers = [Trigger(condition: .appOpen(zoom), action: .switchProfile(talk))]
        var state = TriggerState()
        step(&settings, TriggerFacts(runningApps: [zoom]), &state)
        let during = step(&settings, TriggerFacts(), &state, suspended: true)
        #expect(during.profileChange == nil)
        #expect(settings.activeProfile == talk)
        step(&settings, TriggerFacts(), &state)
        #expect(settings.activeProfile == work)
    }

    @Test func aTriggerForTheProfileAlreadyActiveBringsNothingBack() {
        var (settings, work, _) = makeSettings()
        settings.triggers = [Trigger(condition: .onBattery, action: .switchProfile(work))]
        var state = TriggerState()
        let started = step(&settings, TriggerFacts(isOnBattery: true), &state)
        #expect(started.profileChange == nil)
        let ended = step(&settings, TriggerFacts(), &state)
        #expect(ended.profileChange == nil)
        #expect(settings.activeProfile == work)
    }
}

@Suite struct TriggerScheduleTests {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test func withoutTriggersNothingIsWatched() {
        #expect(TriggerSchedule.needs(of: []).isEmpty)
        #expect(TriggerSchedule.boundaries(of: []).isEmpty)
        #expect(TriggerSchedule.nextBoundary(after: date(27, 12, 0), boundaries: [], calendar: Self.utc) == nil)
    }

    @Test func onlyWhatEnabledTriggersNeedIsWatched() {
        let triggers = [
            Trigger(condition: .appOpen("us.zoom.xos"), action: .focus),
            Trigger(condition: .batteryAtOrBelow(20), action: .focus),
            Trigger(isEnabled: false, condition: .cameraOrMicrophone, action: .focus),
            Trigger(isEnabled: false, condition: .timeOfDay(from: at(9), to: at(17)), action: .focus),
        ]
        #expect(TriggerSchedule.needs(of: triggers) == [.runningApps, .power])
        #expect(TriggerSchedule.boundaries(of: triggers).isEmpty)
        let all: [TriggerCondition] = [.appInFront("x"), .onBattery, .externalDisplay, .timeOfDay(from: 1, to: 2), .cameraOrMicrophone]
        #expect(TriggerSchedule.needs(of: all.map { Trigger(condition: $0, action: .focus) })
            == [.frontmostApp, .power, .displays, .clock, .cameraAndMicrophone])
    }

    @Test func boundariesAreTheStartsAndEndsOfTimeRanges() {
        let triggers = [
            Trigger(condition: .timeOfDay(from: at(22), to: at(7)), action: .focus),
            Trigger(condition: .timeOfDay(from: at(9), to: at(9)), action: .focus),
            Trigger(condition: .timeOfDay(from: at(7), to: at(12)), action: .focus),
        ]
        #expect(TriggerSchedule.boundaries(of: triggers) == [at(22), at(7), at(12)])
    }

    @Test func theOneTimerAimsAtTheNextBoundary() {
        let boundaries: Set<Int> = [at(18), at(8)]
        #expect(TriggerSchedule.nextBoundary(after: date(27, 17, 30), boundaries: boundaries, calendar: Self.utc) == date(27, 18, 0))
        #expect(TriggerSchedule.nextBoundary(after: date(27, 18, 0), boundaries: boundaries, calendar: Self.utc) == date(28, 8, 0),
                "at a boundary, the next one")
        #expect(TriggerSchedule.nextBoundary(after: date(27, 23, 59, 30), boundaries: boundaries, calendar: Self.utc) == date(28, 8, 0))
        #expect(TriggerSchedule.nextBoundary(after: date(27, 7, 59, 59), boundaries: [0], calendar: Self.utc) == date(28, 0, 0))
    }

    @Test func minutesSinceMidnight() {
        #expect(TriggerSchedule.minutesSinceMidnight(of: date(27, 0, 0), calendar: Self.utc) == 0)
        #expect(TriggerSchedule.minutesSinceMidnight(of: date(27, 18, 42, 59), calendar: Self.utc) == at(18, 42))
    }
}

@Suite struct TriggerPlanningTests {
    let files = Drawer(name: "Files & Cloud", mark: .symbol("cloud.fill"), category: .files)
    let drive = IconID(bundleID: "com.google.drivefs")
    let bridge = IconID(bundleID: "com.protonmail.bridge")
    let pli = IconID(bundleID: "ch.rubencatalao.pli")

    func layout() -> Layout {
        var layout = Layout(drawers: [files])
        layout.assign(drive, to: .drawer(files.id))
        layout.assign(bridge, to: .drawer(files.id))
        layout.assign(pli, to: .hidden)
        return layout
    }

    @Test func shownIconsGoToTheMenuBarWithoutChangingTheLayout() {
        let layout = layout()
        let plan = LayoutPlanner.plan(layout: layout, snapshot: sampleBar(), granularity: .icon, categories: [:], shownIcons: [pli])
        #expect(plan.visible.contains(pli))
        #expect(plan.concealed == [drive, bridge])
        #expect(layout.placement(of: pli, category: nil) == .hidden)
    }

    @Test func aShownDrawerShowsEveryIconItHolds() {
        let categories = [IconID(bundleID: "com.getdropbox.dropbox"): CategoryID.files]
        var bar = sampleBar()
        bar = MenuBarSnapshot(icons: bar.icons + [icon("com.getdropbox.dropbox", x: 940)])
        let plan = LayoutPlanner.plan(layout: layout(), snapshot: bar, granularity: .icon, categories: categories, shownDrawers: [files.id])
        #expect(plan.visible.isSuperset(of: [drive, bridge, IconID(bundleID: "com.getdropbox.dropbox")]), "new icons sorted into it too")
        #expect(plan.concealed == [pli])
    }

    @Test func shownIconsCountOnlyInTheNormalMode() {
        let focus = LayoutPlanner.plan(layout: layout(), snapshot: sampleBar(), granularity: .icon, categories: [:], mode: .focus,
                                       shownIcons: [pli], shownDrawers: [files.id])
        #expect(focus.concealed.contains(pli))
        #expect(focus.concealed.contains(drive))
    }
}

import Foundation
import Testing
import TiroirCore
@testable import TiroirSystem

/// Takes shortcuts in memory: nothing is registered with macOS.
@MainActor
final class FakeRegistrar: HotKeyRegistrar {
    var taken: Set<Shortcut> = []
    private(set) var registered: [UInt32: (shortcut: Shortcut, onPress: @MainActor () -> Void)] = [:]
    private var next: UInt32 = 1

    func register(_ shortcut: Shortcut, onPress: @escaping @MainActor () -> Void) -> HotKeyRegistration? {
        guard !taken.contains(shortcut) else { return nil }
        defer { next += 1 }
        registered[next] = (shortcut, onPress)
        return HotKeyRegistration(id: next)
    }

    func unregister(_ registration: HotKeyRegistration) {
        registered[registration.id] = nil
    }

    func press(_ shortcut: Shortcut) {
        for entry in registered.values where entry.shortcut == shortcut { entry.onPress() }
    }
}

@MainActor
@Suite struct ProfileShortcutTests {
    let workKey = Shortcut(keyCode: 13, modifiers: [.control, .option, .command], keyLabel: "W")
    let homeKey = Shortcut(keyCode: 4, modifiers: [.control, .option, .command], keyLabel: "H")

    func settings() -> (settings: TiroirSettings, work: UUID, home: UUID) {
        var settings = TiroirSettings(hasCompletedWelcome: true)
        let work = settings.saveCurrentAsProfile(named: "Work")
        let home = settings.saveCurrentAsProfile(named: "Home")
        settings.setShortcut(workKey, ofProfile: work)
        settings.setShortcut(homeKey, ofProfile: home)
        return (settings, work, home)
    }

    @Test func eachProfileShortcutIsWanted() {
        let (settings, work, home) = settings()
        let wanted = ShortcutCenter.wanted(from: settings)
        #expect(wanted[.profile(work)] == workKey)
        #expect(wanted[.profile(home)] == homeKey)
        #expect(wanted[.search] == .defaultSearch)
    }

    @Test func pressingAProfileShortcutAsksForThatProfile() {
        let (settings, work, _) = settings()
        let registrar = FakeRegistrar()
        var pressed: [ShortcutCenter.Action] = []
        let center = ShortcutCenter(registrar: registrar) { pressed.append($0) }
        #expect(center.apply(ShortcutCenter.wanted(from: settings)).isEmpty)
        registrar.press(workKey)
        #expect(pressed == [.profile(work)])
    }

    @Test func aTakenProfileShortcutIsRefused() {
        let (settings, _, home) = settings()
        let registrar = FakeRegistrar()
        registrar.taken = [homeKey]
        let center = ShortcutCenter(registrar: registrar) { _ in }
        #expect(center.apply(ShortcutCenter.wanted(from: settings)) == [.profile(home)])
    }

    @Test func deletingAProfileReleasesItsShortcut() {
        var (settings, work, _) = settings()
        let registrar = FakeRegistrar()
        let center = ShortcutCenter(registrar: registrar) { _ in }
        center.apply(ShortcutCenter.wanted(from: settings))
        settings.deleteProfile(work)
        center.apply(ShortcutCenter.wanted(from: settings))
        #expect(!registrar.registered.values.contains { $0.shortcut == workKey })
        #expect(registrar.registered.values.contains { $0.shortcut == homeKey })
    }
}

@MainActor
@Suite struct TriggerSensorTests {
    /// Tiroir runs no timer and watches nothing at rest: without triggers, the sensors stay idle.
    @Test func withoutTriggersNothingRuns() {
        let sensors = TriggerSensors()
        sensors.watch(TriggerSchedule.needs(of: []), boundaries: [])
        #expect(sensors.isIdle)
        let facts = sensors.facts()
        #expect(facts.runningApps.isEmpty && facts.frontmostApp == nil && !facts.isOnBattery && facts.batteryPercent == nil)
    }

    @Test func aTimeRangeTakesOneTimerThatGoesWithIt() {
        let sensors = TriggerSensors()
        let triggers = [Trigger(condition: .timeOfDay(from: 9 * 60, to: 17 * 60), action: .focus)]
        sensors.watch(TriggerSchedule.needs(of: triggers), boundaries: TriggerSchedule.boundaries(of: triggers))
        #expect(!sensors.isIdle)
        sensors.watch(TriggerSchedule.needs(of: []), boundaries: [])
        #expect(sensors.isIdle)
    }

    @Test func turningATriggerOffStopsItsSensor() {
        let sensors = TriggerSensors()
        var trigger = Trigger(condition: .appInFront("com.apple.iWork.Keynote"), action: .focus)
        sensors.watch(TriggerSchedule.needs(of: [trigger]), boundaries: [])
        #expect(sensors.needs == [.frontmostApp])
        trigger.isEnabled = false
        sensors.watch(TriggerSchedule.needs(of: [trigger]), boundaries: [])
        #expect(sensors.isIdle)
    }
}

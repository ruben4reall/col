import AppKit
import ColCore

/// Your Mac at a glance: the weather, a Focus turning on, Caps Lock, the battery of your accessories, Pomodoro and the
/// next meeting. Each part runs only while its setting is on, and only on events: nothing here polls. The keyboard
/// backlight and the microphone's mute live with the other system displays (SystemActivities).
@MainActor
final class Glance {
    let weather = WeatherModel()
    let pomodoro = PomodoroModel()
    let meetings: MeetingWatch
    let focus = FocusMonitor()
    let accessories = AccessoryBatteries()
    let microphone: MicrophoneMute
    private let system: SystemActivities
    private let capsLock = CapsLockMonitor()
    private lazy var microphoneHotKey = HotKey(id: 2, shortcut: HotKey.microphoneShortcut) { [weak self] in
        self?.system.toggleMicrophone()
    }

    var post: ((Activity) -> Void)? {
        didSet { pomodoro.post = post; meetings.post = post }
    }
    var remove: ((String) -> Void)? {
        didSet { pomodoro.remove = remove; meetings.remove = remove }
    }

    private var observers: [NSObjectProtocol] = []
    private var started = false

    init(calendar: CalendarModel, system: SystemActivities) {
        meetings = MeetingWatch(calendar: calendar)
        microphone = system.microphone
        self.system = system
    }

    func start() {
        guard !started else { return }
        started = true
        focus.onChange = { [weak self] on in self?.showFocus(on) }
        capsLock.onChange = { [weak self] on in self?.showCapsLock(on) }
        accessories.onLow = { [weak self] level in self?.showLowBattery(level) }
        // Moments when something may have changed without telling: another app comes forward, the Mac wakes or
        // unlocks. A Focus is read then, and the accessories' batteries.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.readFocus() }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.somethingMayHaveChanged() }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.somethingMayHaveChanged() }
        })
        // Caps Lock waits for Accessibility, which takes effect without a relaunch.
        observers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { self?.apply() } }
        })
        apply()
    }

    /// Any setting changed: start or stop each part as its own setting says.
    func preferencesChanged() {
        apply()
        weather.preferencesChanged()
        pomodoro.preferencesChanged()
        system.microphoneSettingChanged()
    }

    /// The island opened: what it shows should be current.
    func islandOpened() {
        somethingMayHaveChanged()
        meetings.preferencesChanged()
    }

    private func apply() {
        if Preferences.showsCapsLock, MediaKeyTap.isTrusted { capsLock.start() } else { capsLock.stop() }
        if Preferences.showsAccessoryBatteries { accessories.start() } else { accessories.stop() }
        if Preferences.showsFocus { readFocus() } else { focus.reset() }
        if Preferences.mutesMicrophone, Preferences.microphoneHotKeyEnabled { microphoneHotKey.register() } else { microphoneHotKey.unregister() }
        meetings.preferencesChanged()
    }

    private func somethingMayHaveChanged() {
        readFocus()
        if Preferences.showsAccessoryBatteries { accessories.refresh() }
    }

    private func readFocus() {
        guard Preferences.showsFocus else { return }
        focus.refresh()
    }

    // MARK: Brief displays

    private static let focusTint = RGBA(red: 0.37, green: 0.36, blue: 0.9)

    private func showFocus(_ on: Bool) {
        post?(Activity(
            id: "focus",
            priority: .transient,
            compact: CompactPresentation(
                leading: .symbol("moon.fill", tint: on ? Self.focusTint : .white),
                trailing: .text(on ? String(localized: "Focus on", bundle: .module) : String(localized: "Focus off", bundle: .module), tint: on ? Self.focusTint : .white)
            ),
            expires: Date().addingTimeInterval(2.5),
            updated: Date()
        ))
    }

    private func showCapsLock(_ on: Bool) {
        post?(Activity(
            id: "hud",
            priority: .transient,
            compact: CompactPresentation(
                leading: .symbol(on ? "capslock.fill" : "capslock", tint: on ? .green : .white),
                trailing: .text(on ? String(localized: "Caps Lock on", bundle: .module) : String(localized: "Caps Lock off", bundle: .module))
            ),
            expires: Date().addingTimeInterval(1.6),
            updated: Date()
        ))
    }

    private func showLowBattery(_ level: AccessoryLevel) {
        post?(Activity(
            id: "accessory.low",
            priority: .alert,
            compact: CompactPresentation(
                leading: .symbol(level.kind.symbol, tint: .red),
                trailing: .text((Double(level.percent) / 100).formatted(.percent.precision(.fractionLength(0))), tint: .red)
            ),
            expires: Date().addingTimeInterval(5),
            updated: Date()
        ))
    }
}

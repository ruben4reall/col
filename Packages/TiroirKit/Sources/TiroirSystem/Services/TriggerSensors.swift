import AppKit
import IOKit.ps
import TiroirCore

/// Watches what the enabled triggers need, and nothing else (spec: Triggers): apps that launch and quit, the app in
/// front, the power source, the displays, the time of day, and whether a camera or a microphone is in use. Each sensor
/// listens to the system's own notifications and reads its value only when told of a change. The time of day takes one
/// timer to the next start or end of a range, set again at each boundary, after sleep and when the clock changes. With
/// no trigger, nothing here runs. No sensor needs a permission, and nothing leaves the Mac.
@MainActor
public final class TriggerSensors {
    /// Called once after a burst of changes.
    public var onChange: (@MainActor () -> Void)?
    public private(set) var needs: TriggerSensorNeeds = []
    private var boundaries: Set<Int> = []
    private var observations: [TriggerSensorNeeds: [(center: NotificationCenter, token: NSObjectProtocol)]] = [:]
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private let devices = CameraAndMicrophone()
    private var pending: Task<Void, Never>?
    private let delay: Duration

    public init(delay: Duration = .milliseconds(250)) {
        self.delay = delay
        devices.onChange = { [weak self] in self?.changed() }
    }

    /// Nothing watched, no timer: what Tiroir promises at rest when no trigger needs a sensor.
    public var isIdle: Bool {
        observations.isEmpty && timer == nil && powerSource == nil && !devices.isRunning
    }

    /// Starts the sensors these needs call for, stops the others, and aims the clock at the next boundary.
    public func watch(_ needs: TriggerSensorNeeds, boundaries: Set<Int>) {
        let previous = self.needs
        self.needs = needs
        self.boundaries = boundaries
        let all: [TriggerSensorNeeds] = [.runningApps, .frontmostApp, .power, .displays, .clock, .cameraAndMicrophone]
        for need in all where previous.contains(need) != needs.contains(need) {
            if needs.contains(need) { start(need) } else { stop(need) }
        }
        scheduleClock()
    }

    public func stopAll() {
        watch([], boundaries: [])
        pending?.cancel()
        pending = nil
    }

    /// What the sensors read right now. Only what the needs call for is read; the rest keeps its default.
    public func facts(at now: Date = Date()) -> TriggerFacts {
        // The autoupdating calendar follows a change of time zone, as when travelling.
        let minutes = TriggerSchedule.minutesSinceMidnight(of: now, calendar: .autoupdatingCurrent)
        var facts = TriggerFacts(minutesSinceMidnight: minutes)
        if needs.contains(.runningApps) {
            facts.runningApps = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        if needs.contains(.frontmostApp) {
            facts.frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        if needs.contains(.power) {
            let power = Self.power()
            facts.isOnBattery = power.onBattery
            facts.batteryPercent = power.percent
        }
        if needs.contains(.displays) { facts.hasExternalDisplay = Self.hasExternalDisplay() }
        if needs.contains(.cameraAndMicrophone) { facts.isCameraOrMicrophoneInUse = devices.isInUse }
        return facts
    }

    // MARK: Starting and stopping

    private func start(_ need: TriggerSensorNeeds) {
        let workspace = NSWorkspace.shared.notificationCenter
        switch need {
        case .runningApps:
            observe(need, on: workspace, [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification])
        case .frontmostApp:
            observe(need, on: workspace, [NSWorkspace.didActivateApplicationNotification])
        case .displays:
            observe(need, on: .default, [NSApplication.didChangeScreenParametersNotification])
        case .clock:
            observe(need, on: workspace, [NSWorkspace.didWakeNotification])
            observe(need, on: .default, [.NSSystemClockDidChange, .NSSystemTimeZoneDidChange])
        case .power:
            startPower()
        case .cameraAndMicrophone:
            devices.start()
        default:
            break
        }
    }

    private func stop(_ need: TriggerSensorNeeds) {
        for observation in observations[need] ?? [] { observation.center.removeObserver(observation.token) }
        observations[need] = nil
        switch need {
        case .power: stopPower()
        case .cameraAndMicrophone: devices.stop()
        default: break
        }
    }

    private func observe(_ need: TriggerSensorNeeds, on center: NotificationCenter, _ names: [Notification.Name]) {
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.noticed(need) }
            }
            observations[need, default: []].append((center, token))
        }
    }

    private func noticed(_ need: TriggerSensorNeeds) {
        // After sleep or a change of the clock, the timer may aim at the wrong moment.
        if need == .clock { scheduleClock() }
        changed()
    }

    /// One evaluation per burst: an app often starts helpers along with it, and a display change comes in several
    /// notifications.
    private func changed() {
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    // MARK: The time of day

    /// One timer, never repeating, to the next start or end of a time range.
    private func scheduleClock() {
        timer?.invalidate()
        timer = nil
        guard needs.contains(.clock),
              let next = TriggerSchedule.nextBoundary(after: Date(), boundaries: boundaries, calendar: .autoupdatingCurrent) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.noticed(.clock) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Power

    /// IOKit calls back on the main run loop whenever a power source changes: plugged in, unplugged, charge.
    private func startPower() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let sensors = Unmanaged<TriggerSensors>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { sensors.changed() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSource = source
    }

    private func stopPower() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
            CFRunLoopSourceInvalidate(powerSource)
        }
        powerSource = nil
    }

    /// Whether the Mac runs on battery, and the internal battery's charge (nil without one).
    static func power() -> (onBattery: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (false, nil) }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = providing == kIOPSBatteryPowerValue
        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (onBattery, nil) }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return (onBattery, Int((Double(current) * 100 / Double(maximum)).rounded()))
        }
        return (onBattery, nil)
    }

    // MARK: Displays

    /// Whether a display other than the built-in one is connected, lid open or closed.
    static func hasExternalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    isolated deinit {
        stopAll()
    }
}

import Foundation
import IOKit.ps
import Observation

/// Follows the battery through IOKit's power source notifications.
@MainActor
@Observable
final class PowerMonitor {
    struct State: Equatable {
        var level: Double
        var isCharging: Bool
        var onAdapter: Bool
    }

    @ObservationIgnored var onChange: ((_ state: State, _ previous: State?) -> Void)?
    private(set) var state: State?
    @ObservationIgnored private var source: CFRunLoopSource?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() else { return }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        state = Self.read()
    }

    private func refresh() {
        guard let next = Self.read(), next != state else { return }
        let previous = state
        state = next
        onChange?(next, previous)
    }

    static func read() -> State? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            return State(
                level: Double(current) / Double(maximum),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                onAdapter: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }
}

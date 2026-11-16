import AppKit

/// Follows Caps Lock with a monitor of modifier changes: it only sees modifier keys go up and down (never what is
/// typed), cannot hold any back, and runs only while the setting is on. Needs Accessibility, like the volume keys.
@MainActor
final class CapsLockMonitor {
    var onChange: ((Bool) -> Void)?
    private var global: Any?
    private var local: Any?
    private var isOn = NSEvent.modifierFlags.contains(.capsLock)

    var isRunning: Bool { global != nil }

    func start() {
        guard global == nil else { return }
        isOn = NSEvent.modifierFlags.contains(.capsLock)
        global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let on = event.modifierFlags.contains(.capsLock)
            MainActor.assumeIsolated { self?.changed(on) }
        }
        // Col's own windows, the settings for one, do not reach the global monitor.
        local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let on = event.modifierFlags.contains(.capsLock)
            MainActor.assumeIsolated { self?.changed(on) }
            return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }

    private func changed(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        onChange?(on)
    }
}

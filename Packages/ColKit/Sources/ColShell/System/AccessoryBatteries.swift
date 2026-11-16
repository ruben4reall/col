import ColCore
import Foundation
import IOKit
import Observation

/// The battery of Bluetooth mice, keyboards, trackpads and other HID accessories, as IOKit publishes it
/// (`BatteryPercent`). Read when an accessory connects or tells IOKit something changed, and when the island opens or
/// the Mac wakes: nothing is polled. Needs no permission.
@MainActor
@Observable
final class AccessoryBatteries {
    private(set) var levels: [AccessoryLevel] = []
    /// An accessory just ran low.
    @ObservationIgnored var onLow: ((AccessoryLevel) -> Void)?

    @ObservationIgnored private var port: IONotificationPortRef?
    @ObservationIgnored private var iterators: [io_iterator_t] = []
    /// The interest notification of each accessory, by registry entry, released when it goes.
    @ObservationIgnored private var interests: [UInt64: io_object_t] = [:]
    @ObservationIgnored private var watch = LowBatteryWatch()
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var demo = false

    /// The services that carry `BatteryPercent`: the one macOS uses today, and the older Bluetooth HID drivers.
    private static let classes = ["AppleDeviceManagementHIDEventService", "BNBMouseDevice", "BNBTrackpadDevice", "AppleBluetoothHIDKeyboard"]

    var isRunning: Bool { port != nil }

    func start() {
        guard port == nil, !demo, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.classes {
            for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                var iterator: io_iterator_t = 0
                let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching(name), { context, iterator in
                    guard let context else { return }
                    let monitor = Unmanaged<AccessoryBatteries>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { monitor.drain(iterator, connecting: true) }
                }, context, &iterator)
                guard result == KERN_SUCCESS else { continue }
                iterators.append(iterator)
                // Reading the iterator arms it; the services already there are read by refresh().
                drain(iterator, connecting: type == kIOFirstMatchNotification)
            }
        }
        refresh()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        interests.values.forEach { IOObjectRelease($0) }
        iterators.forEach { IOObjectRelease($0) }
        interests = [:]
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
        if !demo { levels = [] }
    }

    /// Accessories connected or left: listen to the new ones, and read every level a moment later, once their battery
    /// has been published.
    private func drain(_ iterator: io_iterator_t, connecting: Bool) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var entry: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entry)
            if !connecting, let interest = interests.removeValue(forKey: entry) {
                IOObjectRelease(interest)
            }
            if connecting, interests[entry] == nil, let port {
                var interest: io_object_t = 0
                let context = Unmanaged.passUnretained(self).toOpaque()
                if IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { context, _, _, _ in
                    guard let context else { return }
                    let monitor = Unmanaged<AccessoryBatteries>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { monitor.refreshSoon() }
                }, context, &interest) == KERN_SUCCESS {
                    interests[entry] = interest
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        if isRunning { refreshSoon() }
    }

    /// Many messages can come at once: one reading for all of them.
    private func refreshSoon() {
        guard pending == nil else { return }
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.refresh()
        }
    }

    func refresh() {
        guard isRunning, !demo else { return }
        var found: [AccessoryLevel] = []
        for name in Self.classes {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { continue }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dictionary = properties?.takeRetainedValue() as? [String: Any],
                   let level = AccessoryLevel.parse(dictionary) {
                    found.append(level)
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        let levels = AccessoryLevel.unique(found)
        if levels != self.levels { self.levels = levels }
        for low in watch.update(levels) { onLow?(low) }
    }

    /// For screenshots: a few accessories stand in for the Mac's.
    func showDemo(_ levels: [AccessoryLevel]) {
        stop()
        demo = true
        self.levels = levels
    }
}

import AppKit
import ColCore

/// Takes over the volume, mute and brightness keys so Col's own display replaces the system's.
///
/// It needs the Accessibility permission, and only listens to system-defined events: typing never reaches it.
/// A key Col cannot honour, such as volume on a display without its own, goes through to macOS untouched.
@MainActor
final class MediaKeyTap {
    /// Returns true when the key was handled and must not reach the system.
    var handler: ((MediaKeyPress, _ fine: Bool) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy settings.
    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, spelled out: the global is not concurrency-safe.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil, Self.isTrusted else { return }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: mediaKeyCallback, userInfo: context
        ) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Returns true to swallow the event.
    fileprivate func shouldSwallow(type: CGEventType, data1: Int?, subtype: Int16?, flags: NSEvent.ModifierFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard subtype == 8, let data1, let press = MediaKeyPress(data1: data1) else { return false }
        // Option alone opens the matching settings pane in macOS; leave that to the system.
        if flags.contains(.option), !flags.contains(.shift) { return false }
        let fine = flags.contains(.option) && flags.contains(.shift)
        return handler?(press, fine) == true
    }
}

private func mediaKeyCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, context: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(context).takeUnretainedValue()
    let nsEvent = type.rawValue == 14 ? NSEvent(cgEvent: event) : nil
    let data1 = nsEvent?.data1, subtype = nsEvent?.subtype.rawValue, flags = nsEvent?.modifierFlags ?? []
    // The tap is installed on the main run loop, so this runs on the main thread.
    let swallow = MainActor.assumeIsolated { tap.shouldSwallow(type: type, data1: data1, subtype: subtype, flags: flags) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

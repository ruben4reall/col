import Foundation
import ObjectiveC

/// Reads and sets the keyboard backlight through CoreBrightness's KeyboardBrightnessClient, the private class behind
/// the backlight keys and Control Center's slider. Looked up at run time and optional: without it, the keys are left
/// to macOS.
@MainActor
enum KeyboardBacklight {
    private typealias Copy = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Set = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias Ask = @convention(c) (AnyObject, Selector, UInt64) -> Bool

    private static let copyIDs = NSSelectorFromString("copyKeyboardBacklightIDs")
    private static let brightness = NSSelectorFromString("brightnessForKeyboard:")
    private static let setBrightness = NSSelectorFromString("setBrightness:forKeyboard:")
    private static let builtIn = NSSelectorFromString("isKeyboardBuiltIn:")

    private static let client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        let client = type.init()
        for selector in [copyIDs, brightness, setBrightness] where !client.responds(to: selector) { return nil }
        return client
    }()

    /// The level the toggle key goes back to after turning the backlight off.
    private static var lastLit: Float = 0.5

    /// The built-in keyboard's backlight, else the first one.
    private static var keyboard: UInt64? {
        guard let client else { return nil }
        let copy = unsafeBitCast(client.method(for: copyIDs), to: Copy.self)
        guard let ids = copy(client, copyIDs)?.takeRetainedValue() as? [NSNumber], !ids.isEmpty else { return nil }
        if client.responds(to: builtIn) {
            let isBuiltIn = unsafeBitCast(client.method(for: builtIn), to: Ask.self)
            if let id = ids.first(where: { isBuiltIn(client, builtIn, $0.uint64Value) }) { return id.uint64Value }
        }
        return ids[0].uint64Value
    }

    static var isAvailable: Bool { keyboard != nil }

    static var level: Double? {
        guard let client, let keyboard else { return nil }
        let get = unsafeBitCast(client.method(for: brightness), to: Get.self)
        return Double(min(max(get(client, brightness, keyboard), 0), 1))
    }

    @discardableResult
    static func set(_ level: Double) -> Bool {
        guard let client, let keyboard else { return false }
        let value = Float(min(max(level, 0), 1))
        if let current = self.level, current > 0 { lastLit = Float(current) }
        let set = unsafeBitCast(client.method(for: setBrightness), to: Set.self)
        return set(client, setBrightness, value, keyboard)
    }

    /// Off, or back to the level it had before; returns the new level.
    static func toggle() -> Double? {
        guard let level else { return nil }
        let next = level > 0 ? 0 : Double(lastLit)
        return set(next) ? next : nil
    }
}

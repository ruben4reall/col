import CoreGraphics
import Foundation

/// Reads and sets the built-in display's brightness through DisplayServices, the private framework behind the
/// brightness keys. Loaded lazily and optional: without it the keys are left to macOS.
@MainActor
enum Brightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: Get, set: Set)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return (unsafeBitCast(get, to: Get.self), unsafeBitCast(set, to: Set.self))
    }()

    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var level: Double? {
        guard let functions, let display = builtInDisplay else { return nil }
        var value: Float = 0
        return functions.get(display, &value) == 0 ? Double(value) : nil
    }

    @discardableResult
    static func set(_ level: Double) -> Bool {
        guard let functions, let display = builtInDisplay else { return false }
        return functions.set(display, Float(min(max(level, 0), 1))) == 0
    }
}

import AppKit

/// A SkyLight space that stays visible above the Lock Screen. Windows moved into it show while the Mac is locked.
///
/// SkyLight is private: every symbol is looked up at run time, and without them the Lock Screen features simply stay
/// off. The approach (a space at the notification-centre-at-lock level) follows SkyLightWindow, MIT licensed; see
/// THIRD-PARTY-NOTICES.md.
@MainActor
final class LockScreenSpace {
    static let shared = LockScreenSpace()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: Int32
    private let addWindows: AddWindows

    /// Nil when SkyLight does not offer what is needed.
    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let level = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }
        connection = unsafeBitCast(main, to: MainConnection.self)()
        space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        // 400: the level of Notification Center over the Lock Screen.
        _ = unsafeBitCast(level, to: SetLevel.self)(connection, space, 400)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [space] as CFArray)
        addWindows = unsafeBitCast(add, to: AddWindows.self)
    }

    func adopt(_ window: NSWindow) {
        window.canBecomeVisibleWithoutLogin = true
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}

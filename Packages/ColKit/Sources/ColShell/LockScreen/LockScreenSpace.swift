import AppKit

/// A SkyLight space that stays visible above the Lock Screen. Windows moved into it show while the Mac is locked.
///
/// SkyLight is private: every symbol is looked up at run time, and without them the Lock Screen features simply stay
/// off. The approach (a space at the notification-centre-at-lock level) follows SkyLightWindow, MIT licensed; see
/// THIRD-PARTY-NOTICES.md.
@MainActor
final class LockScreenSpace {
    /// Nil when SkyLight does not offer what is needed, or would not make the space.
    static let shared = LockScreenSpace()

    /// Why the Lock Screen features cannot work, for the settings; nil while nothing has failed.
    private(set) static var failure: Failure?

    enum Failure: Equatable {
        /// This macOS lacks one of the functions.
        case missingFunctions
        /// SkyLight would not make the space.
        case refused
    }

    // A connection id is a 32-bit integer; a space id is 64 bits (CGSSpaceID). Read as 32 bits, the id of the space
    // came back cut in half on recent macOS, and windows were sent to a space that does not exist.
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SetLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private struct Functions {
        let main: MainConnection
        let create: SpaceCreate
        let setLevel: SetLevel
        let show: ShowSpaces
        let add: AddWindows
    }

    private static func load() -> Functions? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let level = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }
        return Functions(
            main: unsafeBitCast(main, to: MainConnection.self),
            create: unsafeBitCast(create, to: SpaceCreate.self),
            setLevel: unsafeBitCast(level, to: SetLevel.self),
            show: unsafeBitCast(show, to: ShowSpaces.self),
            add: unsafeBitCast(add, to: AddWindows.self)
        )
    }

    /// True when this macOS has what the Lock Screen features need, checked without making anything.
    static var isSupported: Bool { failure == nil && load() != nil }

    private let connection: Int32
    private let space: UInt64
    private let addWindows: AddWindows

    private init?() {
        guard let functions = Self.load() else {
            Self.failure = .missingFunctions
            return nil
        }
        connection = functions.main()
        space = functions.create(connection, 1, 0)
        guard connection != 0, space != 0 else {
            Self.failure = .refused
            return nil
        }
        // 400: the level of Notification Center over the Lock Screen.
        _ = functions.setLevel(connection, space, 400)
        _ = functions.show(connection, [NSNumber(value: space)] as CFArray)
        addWindows = functions.add
    }

    /// Moves a window into the space. The window must be on screen already: SkyLight needs its number.
    func adopt(_ window: NSWindow) {
        window.canBecomeVisibleWithoutLogin = true
        guard window.windowNumber > 0 else { return }
        // What it returns is not documented anywhere: it is not read.
        _ = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}

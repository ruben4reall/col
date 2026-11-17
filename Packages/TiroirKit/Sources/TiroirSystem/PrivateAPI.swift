import AppKit
import CoreGraphics
import Foundation

/// Every private macOS function Tiroir uses, in one file (spec 4.5). Each one is looked up at run time: when a macOS
/// update removes or renames it, its feature turns off and Tiroir says so in Settings; nothing crashes.
public enum PrivateAPI {
    // MARK: macOS 27: MenuBarAgent's restriction

    /// The menu bar half of exam (assessment) mode, in the private `MenuBarClientCore` framework: "show only these
    /// system items and these apps". macOS 27 draws the whole menu bar in one agent, and this restriction is the only
    /// way another app can take icons out of it. Technique from MenuBarHider (MIT) and Ellipsis (Apache-2.0),
    /// rewritten; see THIRD-PARTY-NOTICES.md.
    public struct MenuBarRestrictionClasses: @unchecked Sendable {
        let configuration: NSObject.Type
        let assertion: NSObject.Type
    }

    static let menuBarClientCorePath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    static let configurationInitializer = "initWithAllowedSystemItems:allowedBundleIdentifiers:"
    static let activateSelector = "activateWithConfiguration:completionHandler:"
    static let invalidateSelector = "invalidate"

    /// The two classes, or nil when this macOS does not have them (macOS 26 and earlier, or a later change). Every
    /// selector is checked first: an unchecked message would crash instead of degrading.
    public static let menuBarRestriction: MenuBarRestrictionClasses? = {
        guard dlopen(menuBarClientCorePath, RTLD_NOW) != nil,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              configuration.instancesRespond(to: NSSelectorFromString(configurationInitializer)),
              assertion.instancesRespond(to: NSSelectorFromString(activateSelector)),
              assertion.instancesRespond(to: NSSelectorFromString(invalidateSelector)) else { return nil }
        return MenuBarRestrictionClasses(configuration: configuration, assertion: assertion)
    }()

    /// One live restriction. MenuBarAgent drops it when `invalidate()` is called or when Tiroir's process ends.
    public final class MenuBarAssertion: @unchecked Sendable {
        fileprivate let object: NSObject
        fileprivate init(object: NSObject) { self.object = object }

        public func invalidate() {
            _ = object.perform(NSSelectorFromString(PrivateAPI.invalidateSelector))
        }
    }

    /// Starts a restriction that shows every system item and only the apps in `allowedBundleIdentifiers`. The
    /// completion runs on an arbitrary queue once MenuBarAgent has answered, with its error if it refused.
    public static func activateMenuBarRestriction(
        allowedBundleIdentifiers: [String], systemItems: [NSNumber] = allSystemItems,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> MenuBarAssertion? {
        guard let classes = menuBarRestriction else { return nil }
        guard let allocated = (classes.configuration as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let configuration = allocated.perform(
                  NSSelectorFromString(configurationInitializer), with: systemItems as NSArray,
                  with: allowedBundleIdentifiers as NSArray)?.takeRetainedValue() else { return nil }
        let object = classes.assertion.init()
        // `alloc` hands over +1, `init` consumes it and returns +1 that Tiroir owns (takeRetainedValue above).
        let handler: @convention(block) (Any?) -> Void = { error in completion(error as? Error) }
        _ = object.perform(NSSelectorFromString(activateSelector), with: configuration, with: handler)
        return MenuBarAssertion(object: object)
    }

    /// MenuBarAgent names system items by small integers (the clock, Wi-Fi, Control Center…); codes it does not know
    /// are ignored, so a generous range keeps every one of them, including those later builds add.
    public static let allSystemItems: [NSNumber] = (0..<64).map { NSNumber(value: $0) }

    // MARK: macOS 26: the pointer while icons move

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    /// Lets Tiroir hide and show the pointer while another app is in front, so the synthetic Command-drags that move
    /// icons on macOS 26 do not show the pointer jumping. Without it the pointer blinks; nothing else changes.
    @MainActor @discardableResult
    public static func allowCursorChangesInBackground() -> Bool {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let mainSymbol = dlsym(skyLight, "SLSMainConnectionID") ?? dlsym(skyLight, "CGSMainConnectionID"),
              let setSymbol = dlsym(skyLight, "SLSSetConnectionProperty") ?? dlsym(skyLight, "CGSSetConnectionProperty")
        else { return false }
        let mainConnection = unsafeBitCast(mainSymbol, to: MainConnectionID.self)
        let setProperty = unsafeBitCast(setSymbol, to: SetConnectionProperty.self)
        let connection = mainConnection()
        return setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }

    /// Whether this Mac has the macOS 27 restriction.
    public static var hasMenuBarRestriction: Bool { menuBarRestriction != nil }
}

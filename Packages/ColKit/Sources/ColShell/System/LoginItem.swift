import Foundation
import ServiceManagement

/// Opening Col at login. macOS keeps a single login item for Col's identifier and opens the copy that registered it
/// last: a development build that registered would take the place of the Col in Applications at every login, a copy
/// its updates never reach. So a development build never registers nor unregisters, and leaves the item as the
/// installed Col set it; the installed Col, opened again, takes it back (NameChange.followLoginItem).
enum LoginItem {
    /// A build of the source: a Debug build, or any copy run from a build folder.
    static var isDevelopmentCopy: Bool {
        #if DEBUG
        return true
        #else
        return isBuildFolder(Bundle.main.bundleURL.path)
        #endif
    }

    /// Whether `path` lies in a folder where builds land, Xcode's or SwiftPM's.
    static func isBuildFolder(_ path: String) -> Bool {
        ["/Build/Products/", "/DerivedData/", "/.build/"].contains { path.contains($0) }
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns opening at login on or off, for the installed Col only.
    static func set(_ enabled: Bool) throws {
        guard !isDevelopmentCopy else { return }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

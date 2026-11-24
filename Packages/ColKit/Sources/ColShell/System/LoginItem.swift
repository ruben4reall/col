import Foundation
import ServiceManagement

/// Opening Col at login. macOS keeps a single login item for Col's identifier and opens the copy that registered it
/// last: a development build that registered would take the place of the Col in Applications at every login, a copy
/// its updates never reach. So a development build never registers nor unregisters, and leaves the item as the
/// installed Col set it; the installed Col, opened in a new version, takes it back (`reclaimIfNeeded`).
@MainActor
public enum LoginItem {
    /// A build of the source: a Debug build, or any copy run from a build folder or beside another Col.
    static var isDevelopmentCopy: Bool {
        #if DEBUG
        return true
        #else
        return AppLocation.isDevelopmentBuild
        #endif
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    private static let reclaimedKey = "loginItemReclaimedVersion"

    /// Once per version, while opening at login is on, the installed Col registers itself again: macOS then opens this
    /// very copy at login, even if a development build or a copy elsewhere had taken the login item before.
    public static func reclaimIfNeeded(defaults: UserDefaults = .standard) {
        guard !isDevelopmentCopy, isEnabled else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard defaults.string(forKey: reclaimedKey) != version else { return }
        try? SMAppService.mainApp.register()
        defaults.set(version, forKey: reclaimedKey)
    }

    /// Turns opening at login on or off, for the installed Col only.
    static func set(_ enabled: Bool) throws {
        guard !isDevelopmentCopy else { return }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

import Foundation
import Intents
import Observation

/// Whether a Focus is on, through Intents' Focus status: macOS says only that one is on, never which. There is no
/// notification of the change, so it is read when something happens anyway: the island opening, another app coming
/// forward, the Mac waking or unlocking.
@MainActor
@Observable
final class FocusMonitor {
    /// Nil until read, or while Col may not read it.
    private(set) var isFocused: Bool?
    /// Read when the feature is in use, never before: the island does not touch Focus status while it is off.
    private(set) var authorization: INFocusStatusAuthorizationStatus = .notDetermined
    /// A Focus turned on (true) or off (false) since the last reading.
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    /// Asked for through PermissionCenter, when the setting is turned on.
    var isAuthorized: Bool { authorization == .authorized }

    func readAuthorization() {
        authorization = INFocusStatusCenter.default.authorizationStatus
    }

    func refresh() {
        readAuthorization()
        guard isAuthorized, let focused = INFocusStatusCenter.default.focusStatus.isFocused else {
            isFocused = nil
            return
        }
        let previous = isFocused
        isFocused = focused
        if let previous, previous != focused { onChange?(focused) }
    }

    /// Turned off in the settings: forget, so turning it on again does not announce a change seen long ago.
    func reset() {
        isFocused = nil
    }
}

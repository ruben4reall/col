import Foundation
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac and its display awake, like caffeinate, until turned off.
@MainActor
@Observable
final class KeepAwake {
    private(set) var isOn = false
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored var changed: ((Bool) -> Void)?

    func toggle() {
        isOn ? stop() : start()
    }

    func start() {
        guard !isOn else { return }
        let reason = "Col: keep awake" as CFString
        if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess {
            isOn = true
            changed?(true)
        }
    }

    func stop() {
        guard isOn else { return }
        IOPMAssertionRelease(assertion)
        isOn = false
        changed?(false)
    }
}

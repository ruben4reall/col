import CoreLocation
import Foundation
import Observation

/// The Mac's location, for the weather only: asked for when the user turns the weather on without typing a city, read
/// once per refresh at the accuracy of a town, and never kept beyond memory.
@MainActor
@Observable
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAccess()

    private(set) var status: CLAuthorizationStatus
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    private override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Allowed always, or while in use: macOS 11 and later may answer the latter, whose name Swift hides on the Mac.
    var isAllowed: Bool { status == .authorizedAlways || status.rawValue == 4 }
    var canAsk: Bool { status == .notDetermined }

    /// Shows macOS's prompt; the answer arrives through the delegate.
    func request() {
        guard canAsk else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Where the Mac is now, to about a kilometre; nil when it cannot tell or may not.
    func current() async -> CLLocation? {
        guard isAllowed else { return nil }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { manager.requestLocation() }
        }
    }

    private func answer(_ location: CLLocation?) {
        let waiting = self.waiting
        self.waiting = []
        waiting.forEach { $0.resume(returning: location) }
    }

    // The manager was made on the main thread, so it calls back there.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            self.status = status
            if !self.isAllowed { self.answer(nil) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        MainActor.assumeIsolated { self.answer(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { self.answer(nil) }
    }
}

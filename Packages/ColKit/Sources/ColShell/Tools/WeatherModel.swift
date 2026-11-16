import ColCore
import CoreLocation
import Foundation
import Observation

/// The weather where you are, or in the city you typed, from Open-Meteo. It is asked for only while something shows
/// it (a widget, the Lock Screen) and at most every 30 minutes; nothing is fetched while the island sits closed.
@MainActor
@Observable
final class WeatherModel {
    enum State: Equatable {
        /// Weather is off in the settings.
        case off
        /// Following the Mac's location, which macOS has not been asked for yet.
        case needsLocation
        /// Location Services said no: a city typed in the settings works instead.
        case locationDenied
        case loading
        case ready
        /// Offline, or the service did not answer, before any report came.
        case failed
    }

    private(set) var report: WeatherReport?
    private(set) var state: State = .off
    /// The city typed in the settings; nil for the Mac's location.
    private(set) var place: WeatherPlace? = Preferences.weatherPlace

    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var lastSuccess: Date?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var fetching: Task<Void, Never>?
    @ObservationIgnored private var nextRefresh: Task<Void, Never>?
    /// No cookies, no cache, nothing written to disk.
    private static let session = URLSession(configuration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return configuration
    }())

    init() {
        updateState()
    }

    /// A view that shows the weather appeared: fetch if the last report is old, and keep it fresh while it shows.
    func watch() {
        watchers += 1
        guard watchers == 1 else { return }
        refreshIfDue()
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        nextRefresh?.cancel()
        nextRefresh = nil
    }

    /// The settings changed: a new place, or weather turned on or off. A report for another place is dropped.
    func preferencesChanged() {
        let place = Preferences.weatherPlace
        if place != self.place || !Preferences.showsWeather {
            self.place = place
            report = nil
            lastSuccess = nil
            lastAttempt = nil
            fetching?.cancel()
            fetching = nil
        }
        updateState()
        if watchers > 0 { refreshIfDue() }
    }

    /// Asks macOS for the location, when the weather follows it; the report comes once it is allowed.
    func requestLocation() {
        LocationAccess.shared.request()
    }

    /// Location Services answered: try again with the new answer.
    func locationAuthorizationChanged() {
        updateState()
        if watchers > 0 { refreshIfDue() }
    }

    private func updateState() {
        guard Preferences.showsWeather else { state = .off; return }
        if place == nil, !LocationAccess.shared.isAllowed {
            state = LocationAccess.shared.canAsk ? .needsLocation : .locationDenied
            return
        }
        if report != nil { state = .ready }
        else if fetching != nil || lastAttempt == nil { state = .loading }
        else { state = .failed }
    }

    private func refreshIfDue() {
        updateState()
        guard state != .off, state != .needsLocation, state != .locationDenied else { return }
        let now = Date()
        if fetching == nil, WeatherRefresh.isDue(lastSuccess: lastSuccess, lastAttempt: lastAttempt, now: now) {
            fetch()
        } else {
            scheduleNext()
        }
    }

    /// While something shows the weather, one wake-up when the report is due again, or when a failed try may be made
    /// again; none otherwise.
    private func scheduleNext() {
        nextRefresh?.cancel()
        guard watchers > 0, fetching == nil, let next = WeatherRefresh.nextAttempt(lastSuccess: lastSuccess, lastAttempt: lastAttempt) else { return }
        let delay = max(next.timeIntervalSinceNow, 1)
        nextRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshIfDue()
        }
    }

    private func fetch() {
        lastAttempt = Date()
        let place = place
        let session = Self.session
        fetching = Task { @MainActor [weak self] in
            var coordinate = place.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if coordinate == nil { coordinate = await LocationAccess.shared.current()?.coordinate }
            var report: WeatherReport?
            if let coordinate {
                let url = OpenMeteo.forecastURL(latitude: coordinate.latitude, longitude: coordinate.longitude)
                if let (data, response) = try? await session.data(from: url),
                   (response as? HTTPURLResponse)?.statusCode == 200 {
                    report = try? WeatherReport.decode(data)
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.fetching = nil
            if let report {
                self.report = report
                self.lastSuccess = self.lastAttempt
            }
            self.updateState()
            self.scheduleNext()
        }
        updateState()
    }

    /// Places named like `name`, for the settings' search. Only the name typed is sent.
    static func search(_ name: String) async -> [WeatherPlace] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        guard let url = OpenMeteo.searchURL(for: name, language: language),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return [] }
        return (try? WeatherPlace.decodeSearch(data)) ?? []
    }

    /// For screenshots: a report stands in for the network.
    func showDemo(_ report: WeatherReport, place: WeatherPlace?) {
        self.place = place
        self.report = report
        lastSuccess = Date()
        lastAttempt = lastSuccess
        state = .ready
    }
}

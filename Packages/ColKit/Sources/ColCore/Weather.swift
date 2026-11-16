import Foundation

/// The sky, from the WMO weather code Open-Meteo gives.
public enum WeatherCondition: String, Equatable, Sendable, CaseIterable {
    case clear, mainlyClear, partlyCloudy, overcast, fog, drizzle, freezingDrizzle, rain, heavyRain, freezingRain
    case snow, rainShowers, snowShowers, thunderstorm, hail, unknown

    public init(code: Int) {
        self = switch code {
        case 0: .clear
        case 1: .mainlyClear
        case 2: .partlyCloudy
        case 3: .overcast
        case 45, 48: .fog
        case 51, 53, 55: .drizzle
        case 56, 57: .freezingDrizzle
        case 61, 63: .rain
        case 65: .heavyRain
        case 66, 67: .freezingRain
        case 71, 73, 75, 77: .snow
        case 80, 81, 82: .rainShowers
        case 85, 86: .snowShowers
        case 95: .thunderstorm
        case 96, 99: .hail
        default: .unknown
        }
    }

    /// The SF Symbol for this sky, by day or by night. Every one has a multicolour version.
    public func symbol(isDay: Bool) -> String {
        switch self {
        case .clear, .mainlyClear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .freezingDrizzle, .freezingRain: "cloud.sleet.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .snow, .snowShowers: "cloud.snow.fill"
        case .rainShowers: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .hail: "cloud.hail.fill"
        case .unknown: "thermometer.medium"
        }
    }
}

/// Today's weather at one place: now, today's high and low, and the hours ahead. Temperatures are in degrees Celsius;
/// the island shows them in the unit of the Mac.
public struct WeatherReport: Equatable, Sendable {
    public struct Hour: Equatable, Sendable {
        public var time: Date
        public var temperature: Double
        public var condition: WeatherCondition
        public var isDay: Bool

        public init(time: Date, temperature: Double, condition: WeatherCondition, isDay: Bool) {
            self.time = time
            self.temperature = temperature
            self.condition = condition
            self.isDay = isDay
        }
    }

    public var temperature: Double
    public var condition: WeatherCondition
    public var isDay: Bool
    public var high: Double?
    public var low: Double?
    public var hours: [Hour]
    public var timeZone: TimeZone?

    public init(temperature: Double, condition: WeatherCondition, isDay: Bool, high: Double?, low: Double?, hours: [Hour], timeZone: TimeZone? = nil) {
        self.temperature = temperature
        self.condition = condition
        self.isDay = isDay
        self.high = high
        self.low = low
        self.hours = hours
        self.timeZone = timeZone
    }

    public var symbol: String { condition.symbol(isDay: isDay) }

    /// The next `count` hours after `date`, starting with the first full hour to come.
    public func nextHours(after date: Date, count: Int) -> [Hour] {
        Array(hours.filter { $0.time > date }.prefix(count))
    }

    /// Reads Open-Meteo's answer to `OpenMeteo.forecastURL`, whose times are Unix timestamps.
    public static func decode(_ data: Data) throws -> WeatherReport {
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        var hours: [Hour] = []
        if let hourly = answer.hourly {
            for (index, time) in hourly.time.enumerated() {
                guard let temperature = hourly.temperature[safe: index] ?? nil else { continue }
                let code = hourly.code[safe: index] ?? nil
                let day = hourly.isDay?[safe: index] ?? nil
                hours.append(Hour(
                    time: Date(timeIntervalSince1970: time), temperature: temperature,
                    condition: WeatherCondition(code: code ?? -1), isDay: (day ?? 1) != 0
                ))
            }
        }
        return WeatherReport(
            temperature: answer.current.temperature,
            condition: WeatherCondition(code: answer.current.code ?? -1),
            isDay: (answer.current.isDay ?? 1) != 0,
            high: answer.daily?.high.first ?? nil,
            low: answer.daily?.low.first ?? nil,
            hours: hours,
            timeZone: answer.timezone.flatMap(TimeZone.init(identifier:))
        )
    }

    private struct Answer: Decodable {
        struct Current: Decodable {
            var temperature: Double
            var code: Int?
            var isDay: Int?
            enum CodingKeys: String, CodingKey { case temperature = "temperature_2m", code = "weather_code", isDay = "is_day" }
        }
        struct Hourly: Decodable {
            var time: [TimeInterval]
            var temperature: [Double?]
            var code: [Int?]
            var isDay: [Int?]?
            enum CodingKeys: String, CodingKey { case time, temperature = "temperature_2m", code = "weather_code", isDay = "is_day" }
        }
        struct Daily: Decodable {
            var high: [Double?]
            var low: [Double?]
            enum CodingKeys: String, CodingKey { case high = "temperature_2m_max", low = "temperature_2m_min" }
        }
        var timezone: String?
        var current: Current
        var hourly: Hourly?
        var daily: Daily?
    }
}

/// A place the user typed, found with Open-Meteo's geocoding.
public struct WeatherPlace: Codable, Equatable, Hashable, Sendable {
    public var name: String
    /// The region and the country, to tell two places of the same name apart.
    public var detail: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String, detail: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Reads Open-Meteo's answer to `OpenMeteo.searchURL`; no match gives an empty list.
    public static func decodeSearch(_ data: Data) throws -> [WeatherPlace] {
        struct Answer: Decodable {
            struct Result: Decodable {
                var name: String
                var latitude: Double
                var longitude: Double
                var country: String?
                var admin1: String?
            }
            var results: [Result]?
        }
        return try JSONDecoder().decode(Answer.self, from: data).results?.map { result in
            let detail = [result.admin1, result.country].compactMap { $0 }.filter { !$0.isEmpty && $0 != result.name }
            return WeatherPlace(name: result.name, detail: detail.isEmpty ? nil : detail.joined(separator: ", "),
                                latitude: result.latitude, longitude: result.longitude)
        } ?? []
    }
}

/// Open-Meteo, a free weather service that needs no key. Only coordinates rounded to about a kilometre are sent.
public enum OpenMeteo {
    /// Coordinates to two decimals: about a kilometre, enough for the weather and no closer to the user's door.
    public static func rounded(_ coordinate: Double) -> Double {
        (coordinate * 100).rounded() / 100
    }

    public static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", rounded(latitude))),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", rounded(longitude))),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components.url!
    }

    /// Places named like `name`, with their names in `language` ("fr", "en"…); nil for a name too short to search.
    public static func searchURL(for name: String, language: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url
    }
}

/// When to ask for the weather again: at most every 30 minutes, and never right after a failed try.
public enum WeatherRefresh {
    public static let interval: TimeInterval = 30 * 60
    /// After a failure (offline, say), the next try waits this long, however often the weather shows.
    public static let retryDelay: TimeInterval = 2 * 60

    /// When to try next: half an hour after the last report, and after a failed try not before `retryDelay`. Nil
    /// before any try.
    public static func nextAttempt(lastSuccess: Date?, lastAttempt: Date?) -> Date? {
        let fresh = lastSuccess.map { $0.addingTimeInterval(interval) }
        guard let lastAttempt, lastAttempt != lastSuccess else { return fresh }
        let retry = lastAttempt.addingTimeInterval(retryDelay)
        return max(fresh ?? retry, retry)
    }

    public static func isDue(lastSuccess: Date?, lastAttempt: Date?, now: Date) -> Bool {
        nextAttempt(lastSuccess: lastSuccess, lastAttempt: lastAttempt).map { now >= $0 } ?? true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

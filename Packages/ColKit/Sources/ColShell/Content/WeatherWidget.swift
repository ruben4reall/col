import ColCore
import SwiftUI

/// Temperatures in the Mac's unit, as the system's Weather writes them: "12°".
enum WeatherFormat {
    static func temperature(_ celsius: Double) -> String {
        let unit = UnitTemperature(forLocale: .current, usage: .weather)
        let value = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value.rounded()
        // Never "-0°".
        return (value == 0 ? 0 : value).formatted(.number.precision(.fractionLength(0))) + "°"
    }

    /// "14" or "2 PM", in the place's own time zone.
    static func hour(_ date: Date, in timeZone: TimeZone?) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        if let timeZone { style.timeZone = timeZone }
        return date.formatted(style)
    }
}

extension WeatherCondition {
    var title: LocalizedStringResource {
        let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
        return switch self {
        case .clear: LocalizedStringResource("Clear", bundle: bundle)
        case .mainlyClear: LocalizedStringResource("Mostly clear", bundle: bundle)
        case .partlyCloudy: LocalizedStringResource("Partly cloudy", bundle: bundle)
        case .overcast: LocalizedStringResource("Cloudy", bundle: bundle)
        case .fog: LocalizedStringResource("Fog", bundle: bundle)
        case .drizzle: LocalizedStringResource("Drizzle", bundle: bundle)
        case .freezingDrizzle: LocalizedStringResource("Freezing drizzle", bundle: bundle)
        case .rain: LocalizedStringResource("Rain", bundle: bundle)
        case .heavyRain: LocalizedStringResource("Heavy rain", bundle: bundle)
        case .freezingRain: LocalizedStringResource("Freezing rain", bundle: bundle)
        case .snow: LocalizedStringResource("Snow", bundle: bundle)
        case .rainShowers: LocalizedStringResource("Showers", bundle: bundle)
        case .snowShowers: LocalizedStringResource("Snow showers", bundle: bundle)
        case .thunderstorm: LocalizedStringResource("Thunderstorms", bundle: bundle)
        case .hail: LocalizedStringResource("Thunderstorms and hail", bundle: bundle)
        case .unknown: LocalizedStringResource("Weather", bundle: bundle)
        }
    }
}

/// The weather where you are, or in your city: now, today's high and low, and on a wide page the hours ahead.
struct WeatherWidget: View {
    let weather: WeatherModel
    let width: WidgetWidth

    var body: some View {
        Group {
            switch weather.state {
            case .ready:
                if let report = weather.report { forecast(report) }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Getting the weather…", bundle: .module)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .off:
                prompt(title: Text("Weather", bundle: .module), detail: Text("From Open-Meteo, where you are or in your city.", bundle: .module),
                       button: Text("Turn On…", bundle: .module)) { SettingsWindow.shared.show(.glance) }
            case .needsLocation:
                prompt(title: Text("Weather where you are", bundle: .module), detail: Text("Or type a city in Settings.", bundle: .module),
                       button: Text("Allow Location", bundle: .module)) { weather.requestLocation() }
            case .locationDenied:
                prompt(title: Text("Location is off", bundle: .module), detail: Text("Type a city in Settings for its weather.", bundle: .module),
                       button: Text("Settings…", bundle: .module)) { SettingsWindow.shared.show(.glance) }
            case .failed:
                prompt(title: Text("No weather right now", bundle: .module), detail: Text("Col asks again in a moment.", bundle: .module),
                       button: nil) {}
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { weather.watch() }
        .onDisappear { weather.unwatch() }
        // Location Services answered the prompt: the weather follows. Not read at all for a city, nor while off.
        .onChange(of: followsLocation ? LocationAccess.shared.status : nil) { weather.locationAuthorizationChanged() }
    }

    private var followsLocation: Bool { weather.state != .off && weather.place == nil }

    @ViewBuilder private func forecast(_ report: WeatherReport) -> some View {
        if width == .full {
            HStack(spacing: 16) {
                now(report).frame(width: 170, alignment: .leading)
                hours(report)
            }
        } else {
            now(report)
        }
    }

    /// The sky and the temperature, large, then the day's high and low and the place.
    private func now(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: report.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 34))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(WeatherFormat.temperature(report.temperature))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(report.condition.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                if let high = report.high, let low = report.low {
                    Text("H \(WeatherFormat.temperature(high))  L \(WeatherFormat.temperature(low))", bundle: .module)
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 0)
                placeLabel
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var placeLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: weather.place == nil ? "location.fill" : "mappin.and.ellipse")
                .font(.system(size: 9, weight: .bold))
            if let place = weather.place {
                Text(verbatim: place.name).lineLimit(1)
            } else {
                Text("Here", bundle: .module)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.tertiaryText)
    }

    /// The next five hours, in the place's own time.
    private func hours(_ report: WeatherReport) -> some View {
        HStack(spacing: 0) {
            ForEach(report.nextHours(after: Date(), count: 5), id: \.time) { hour in
                VStack(spacing: 7) {
                    Text(verbatim: WeatherFormat.hour(hour.time, in: report.timeZone))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    Image(systemName: hour.condition.symbol(isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 17))
                        .frame(height: 22)
                    Text(verbatim: WeatherFormat.temperature(hour.temperature))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.fill))
    }

    private func prompt(title: Text, detail: Text, button: Text?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    detail
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let button {
                IslandChip(symbol: "arrow.forward", title: button, action: action)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.fill))
    }
}

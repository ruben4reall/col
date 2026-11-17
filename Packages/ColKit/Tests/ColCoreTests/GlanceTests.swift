import Foundation
import Testing
@testable import ColCore

struct WeatherTests {
    /// Open-Meteo's answer for Paris, cut to four hours.
    static let forecast = Data("""
    {"latitude":48.853382,"longitude":2.355208,"utc_offset_seconds":3600,"timezone":"Europe/Paris",
     "current":{"time":1794845700,"interval":900,"temperature_2m":12.1,"weather_code":3,"is_day":0},
     "hourly":{"time":[1794841200,1794844800,1794848400,1794852000],
               "temperature_2m":[12.5,12.2,null,11.6],"weather_code":[61,3,3,80],"is_day":[1,1,0,0]},
     "daily":{"time":[1794783600,1794870000],"temperature_2m_max":[12.9,17.2],"temperature_2m_min":[10.7,10.9]}}
    """.utf8)

    @Test func readsTheForecast() throws {
        let report = try WeatherReport.decode(Self.forecast)
        #expect(report.temperature == 12.1)
        #expect(report.condition == .overcast)
        #expect(!report.isDay)
        #expect(report.high == 12.9 && report.low == 10.7)
        #expect(report.timeZone?.identifier == "Europe/Paris")
        // An hour without a temperature is left out.
        #expect(report.hours.map(\.temperature) == [12.5, 12.2, 11.6])
        #expect(report.hours.last?.condition == .rainShowers)
        let next = report.nextHours(after: Date(timeIntervalSince1970: 1794845700), count: 5)
        #expect(next.map(\.time.timeIntervalSince1970) == [1794848400 + 3600])
    }

    @Test func aBrokenAnswerThrows() {
        #expect(throws: (any Error).self) { try WeatherReport.decode(Data("{\"error\":true}".utf8)) }
    }

    @Test func weatherCodesBecomeSymbols() {
        #expect(WeatherCondition(code: 0).symbol(isDay: true) == "sun.max.fill")
        #expect(WeatherCondition(code: 0).symbol(isDay: false) == "moon.stars.fill")
        #expect(WeatherCondition(code: 2).symbol(isDay: false) == "cloud.moon.fill")
        #expect(WeatherCondition(code: 48) == .fog)
        #expect(WeatherCondition(code: 57) == .freezingDrizzle)
        #expect(WeatherCondition(code: 65).symbol(isDay: true) == "cloud.heavyrain.fill")
        #expect(WeatherCondition(code: 75) == .snow)
        #expect(WeatherCondition(code: 81).symbol(isDay: true) == "cloud.sun.rain.fill")
        #expect(WeatherCondition(code: 95).symbol(isDay: true) == "cloud.bolt.rain.fill")
        #expect(WeatherCondition(code: 99) == .hail)
        #expect(WeatherCondition(code: 42) == .unknown)
    }

    @Test func onlyRoundedCoordinatesLeaveTheMac() {
        let url = OpenMeteo.forecastURL(latitude: 46.516_789, longitude: 6.632_821)
        #expect(url.host == "api.open-meteo.com")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "latitude" }?.value == "46.52")
        #expect(query.first { $0.name == "longitude" }?.value == "6.63")
        #expect(query.first { $0.name == "timeformat" }?.value == "unixtime")
        #expect(OpenMeteo.rounded(-0.004) == 0)
    }

    @Test func searchesPlacesByName() throws {
        #expect(OpenMeteo.searchURL(for: " L ", language: "fr") == nil)
        let url = try #require(OpenMeteo.searchURL(for: "Lausanne", language: "fr"))
        #expect(url.host == "geocoding-api.open-meteo.com")
        let answer = Data("""
        {"results":[{"id":2659994,"name":"Lausanne","latitude":46.516,"longitude":6.63282,"country":"Suisse","admin1":"Canton de Vaud"},
                    {"id":1,"name":"Monaco","latitude":43.73,"longitude":7.42,"country":"Monaco"}]}
        """.utf8)
        let places = try WeatherPlace.decodeSearch(answer)
        #expect(places.map(\.name) == ["Lausanne", "Monaco"])
        #expect(places[0].detail == "Canton de Vaud, Suisse")
        // A country named like its town is not repeated.
        #expect(places[1].detail == nil)
        #expect(try WeatherPlace.decodeSearch(Data("{\"generationtime_ms\":0.3}".utf8)).isEmpty)
    }

    @Test func refreshesAtMostEveryHalfHour() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(WeatherRefresh.isDue(lastSuccess: nil, lastAttempt: nil, now: now))
        #expect(!WeatherRefresh.isDue(lastSuccess: now.addingTimeInterval(-60), lastAttempt: now.addingTimeInterval(-60), now: now))
        #expect(WeatherRefresh.isDue(lastSuccess: now.addingTimeInterval(-1800), lastAttempt: now.addingTimeInterval(-1800), now: now))
        // A failed try a moment ago: wait before the next, even with nothing shown yet.
        #expect(!WeatherRefresh.isDue(lastSuccess: nil, lastAttempt: now.addingTimeInterval(-30), now: now))
        #expect(WeatherRefresh.isDue(lastSuccess: nil, lastAttempt: now.addingTimeInterval(-121), now: now))
        #expect(WeatherRefresh.nextAttempt(lastSuccess: now, lastAttempt: now) == now.addingTimeInterval(1800))
        #expect(WeatherRefresh.nextAttempt(lastSuccess: nil, lastAttempt: nil) == nil)
        // A refresh that failed after an old report: tried again two minutes later, not every time it shows.
        let old = now.addingTimeInterval(-3600)
        #expect(WeatherRefresh.nextAttempt(lastSuccess: old, lastAttempt: now) == now.addingTimeInterval(120))
        #expect(!WeatherRefresh.isDue(lastSuccess: old, lastAttempt: now.addingTimeInterval(-60), now: now))
    }
}

struct PomodoroTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func focusThenABreakThenStop() throws {
        let plan = PomodoroPlan.standard
        let focus = Pomodoro(phase: .focus, plan: plan, starting: start)
        #expect(focus.countdown.total == 25 * 60)
        #expect(focus.countdown.isFinished(at: start.addingTimeInterval(25 * 60)))
        let rest = try #require(focus.next(plan: plan, at: start.addingTimeInterval(25 * 60)))
        #expect(rest.phase == .rest)
        #expect(rest.countdown.total == 5 * 60)
        // No new focus starts by itself after a break.
        #expect(rest.next(plan: plan, at: start.addingTimeInterval(30 * 60)) == nil)
    }

    @Test func plansStayWithinBounds() {
        let plan = PomodoroPlan(focusMinutes: 500, breakMinutes: 0)
        #expect(plan.focusMinutes == 90 && plan.breakMinutes == 1)
        #expect(PomodoroPlan(focusMinutes: 50, breakMinutes: 10).duration(of: .rest) == 600)
    }

    @Test func todaysCountStartsAgainTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let evening = Date(timeIntervalSince1970: 1_794_870_000 - 3600) // 23:00 in Zurich
        var tally = PomodoroTally()
        tally.add(at: evening, calendar: calendar)
        tally.add(at: evening.addingTimeInterval(1800), calendar: calendar)
        #expect(tally.count(on: evening, calendar: calendar) == 2)
        let tomorrow = evening.addingTimeInterval(3 * 3600)
        #expect(tally.count(on: tomorrow, calendar: calendar) == 0)
        tally.add(at: tomorrow, calendar: calendar)
        #expect(tally.count(on: tomorrow, calendar: calendar) == 1)
        #expect(tally.day == PomodoroTally.key(for: tomorrow, calendar: calendar))
    }
}

struct MeetingCountdownTests {
    let now = Date(timeIntervalSince1970: 100_000)
    let lead: TimeInterval = 5 * 60

    func event(_ id: String, in minutes: Double, allDay: Bool = false) -> MeetingCountdown.Event {
        MeetingCountdown.Event(id: id, start: now.addingTimeInterval(minutes * 60), isAllDay: allDay)
    }

    @Test func countsDownWithinTheLead() {
        let events = [event("later", in: 20), event("soon", in: 4), event("allDay", in: 1, allDay: true)]
        #expect(MeetingCountdown.current(in: events, now: now, lead: lead)?.id == "soon")
        #expect(MeetingCountdown.current(in: [event("later", in: 6)], now: now, lead: lead) == nil)
    }

    @Test func saysNowForAMomentThenLeaves() {
        let started = event("standup", in: -1)
        #expect(MeetingCountdown.current(in: [started], now: now, lead: lead) == started)
        #expect(MeetingCountdown.hasStarted(started, now: now))
        #expect(MeetingCountdown.current(in: [event("standup", in: -2)], now: now, lead: lead) == nil)
    }

    @Test func darkCalendarColoursAreLiftedOnBlack() {
        #expect(RGBA.green.readableOnBlack == .green)
        let navy = RGBA(red: 0, green: 0, blue: 0.4).readableOnBlack
        #expect(navy.blue > 0.4 && navy.red > 0)
        let luminance = 0.2126 * navy.red + 0.7152 * navy.green + 0.0722 * navy.blue
        #expect(luminance >= 0.2)
    }

    @Test func wakesOnlyWhenSomethingChanges() {
        let events = [event("a", in: 20), event("b", in: 3), event("c", in: 1, allDay: true)]
        // The shown event starts in 3 minutes; the next one enters its window in 15.
        #expect(MeetingCountdown.nextChange(in: events, now: now, lead: lead) == now.addingTimeInterval(3 * 60))
        #expect(MeetingCountdown.nextChange(in: [event("a", in: 20)], now: now, lead: lead) == now.addingTimeInterval(15 * 60))
        #expect(MeetingCountdown.nextChange(in: [event("past", in: -10)], now: now, lead: lead) == nil)
    }
}

struct AccessoryTests {
    @Test func readsMiceKeyboardsAndTrackpads() throws {
        let mouse = try #require(AccessoryLevel.parse([
            "Product": "Magic Mouse", "BatteryPercent": NSNumber(value: 64), "DeviceAddress": "AA-BB-CC-DD-EE-FF",
            "PrimaryUsagePage": NSNumber(value: 1), "PrimaryUsage": NSNumber(value: 2),
        ]))
        #expect(mouse.kind == .mouse && mouse.percent == 64 && mouse.id == "aa-bb-cc-dd-ee-ff")
        #expect(mouse.kind.symbol == "magicmouse.fill")
        #expect(AccessoryLevel.parse(["Product": "Magic Trackpad", "BatteryPercent": NSNumber(value: 9)])?.kind == .trackpad)
        #expect(AccessoryLevel.parse(["Product": "Magic Keyboard with Touch ID", "BatteryPercent": NSNumber(value: 100)])?.kind == .keyboard)
        // Named by its maker, recognized by its usage.
        #expect(AccessoryLevel.parse(["Product": "MX Master 3S", "BatteryPercent": NSNumber(value: 50),
                                      "PrimaryUsagePage": NSNumber(value: 1), "PrimaryUsage": NSNumber(value: 2)])?.kind == .mouse)
        #expect(AccessoryLevel.parse(["Product": "DualSense Wireless Controller", "BatteryPercent": NSNumber(value: 50)])?.kind == .gameController)
    }

    @Test func ignoresWhatIsNotABattery() {
        #expect(AccessoryLevel.parse(["Product": "Magic Mouse"]) == nil)
        #expect(AccessoryLevel.parse(["Product": "Magic Mouse", "BatteryPercent": NSNumber(value: 0)]) == nil)
        #expect(AccessoryLevel.parse(["BatteryPercent": NSNumber(value: 40)]) == nil)
    }

    @Test func oneEntryPerDevice() {
        let keyboard = AccessoryLevel(id: "k", name: "Magic Keyboard", kind: .keyboard, percent: 80)
        let mouse = AccessoryLevel(id: "m", name: "Magic Mouse", kind: .mouse, percent: 40)
        #expect(AccessoryLevel.unique([mouse, keyboard, keyboard]).map(\.id) == ["k", "m"])
    }

    @Test func warnsOnceUnderFifteenPercent() {
        var watch = LowBatteryWatch()
        func mouse(_ percent: Int) -> AccessoryLevel { AccessoryLevel(id: "m", name: "Magic Mouse", kind: .mouse, percent: percent) }
        #expect(watch.update([mouse(20)]).isEmpty)
        #expect(watch.update([mouse(14)]).map(\.percent) == [14])
        #expect(watch.update([mouse(12)]).isEmpty)
        // Charged above the line, it may warn again the next time it runs low.
        #expect(watch.update([mouse(60)]).isEmpty)
        #expect(watch.update([mouse(10)]).count == 1)
        // A device that connects already low is said at once.
        let trackpad = AccessoryLevel(id: "t", name: "Magic Trackpad", kind: .trackpad, percent: 5)
        #expect(watch.update([mouse(10), trackpad]).map(\.id) == ["t"])
    }
}

struct MicrophoneMuteLedgerTests {
    @Test func remembersEachDeviceColMuted() throws {
        var ledger = MicrophoneMuteLedger()
        #expect(ledger.isEmpty)
        ledger.muted("BuiltInMicrophone", method: .mute)
        ledger.muted("USB-Mic", method: .volume, volumeBefore: 0.62)
        #expect(ledger.entry(for: "BuiltInMicrophone") == .init(method: .mute))
        #expect(ledger.entry(for: "USB-Mic")?.volume == 0.62)
        // Muted again while still muted: the volume to give back is still the one from before.
        ledger.muted("USB-Mic", method: .volume, volumeBefore: 0)
        #expect(ledger.entry(for: "USB-Mic")?.volume == 0.62)
        // It survives a restart, written in the settings.
        let decoded = try JSONDecoder().decode(MicrophoneMuteLedger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded == ledger)
        ledger.forget("USB-Mic")
        ledger.forget("BuiltInMicrophone")
        #expect(ledger.isEmpty)
    }

    @Test func givesBackTheVolumeItHad() {
        #expect(MicrophoneMuteLedger.volumeToRestore(.init(method: .volume, volume: 0.4)) == 0.4)
        // A volume unknown, or already at zero, comes back at a usual level rather than silent.
        #expect(MicrophoneMuteLedger.volumeToRestore(.init(method: .volume, volume: nil)) == 0.75)
        #expect(MicrophoneMuteLedger.volumeToRestore(.init(method: .volume, volume: 0)) == 0.75)
    }

    @Test func undoesOnlyWhatIsStillMuted() {
        var ledger = MicrophoneMuteLedger()
        ledger.muted("a", method: .mute)
        ledger.muted("b", method: .mute)
        ledger.muted("c", method: .volume, volumeBefore: 0.5)
        // a: still muted, so given back; b: unmuted elsewhere since, forgotten; c: not connected, kept for later.
        let plan = ledger.reconcile { ["a": true, "b": false][$0] }
        #expect(plan.restore == ["a"])
        #expect(plan.forget == ["b"])
    }
}

struct GlanceSystemTests {
    @Test func backlightKeysAreRead() {
        #expect(MediaKeyPress(data1: (21 << 16) | (0x0A << 8))?.key == .illuminationUp)
        #expect(MediaKeyPress(data1: (22 << 16) | (0x0A << 8))?.key == .illuminationDown)
        #expect(MediaKeyPress(data1: (23 << 16) | (0x0B << 8))?.key == .illuminationToggle)
        #expect(SystemGlyphs.keyboardBacklight(level: 0.2) == "light.min")
        #expect(SystemGlyphs.keyboardBacklight(level: 0.8) == "light.max")
    }

    @Test func aMutedMicrophoneShowsInRed() {
        let red = CompactItem.symbol("mic.slash.fill", tint: .red)
        let orange = CompactItem.symbol("mic.fill", tint: .orange)
        let video = CompactItem.symbol("video.fill", tint: .green)
        #expect(PrivacyIndicator.presentation(microphone: false, camera: false, muted: false, appIcon: false) == nil)
        // Muted while nobody listens: the island still says so, on the side a single wing keeps.
        #expect(PrivacyIndicator.presentation(microphone: false, camera: false, muted: true, appIcon: false) == CompactPresentation(trailing: red))
        #expect(PrivacyIndicator.presentation(microphone: true, camera: false, muted: true, appIcon: true)
            == CompactPresentation(leading: .image(key: "privacy.app"), trailing: red))
        #expect(PrivacyIndicator.presentation(microphone: true, camera: true, muted: true, appIcon: true)
            == CompactPresentation(leading: video, trailing: red))
        // The app that listens on the left, the microphone on the right.
        #expect(PrivacyIndicator.presentation(microphone: true, camera: false, muted: false, appIcon: true)
            == CompactPresentation(leading: .image(key: "privacy.app"), trailing: orange))
        #expect(PrivacyIndicator.presentation(microphone: false, camera: true, muted: false, appIcon: false)
            == CompactPresentation(trailing: video))
    }

    @Test func dictationThatStartsAndStopsIsAnnouncedOnce() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(PrivacyIndicator.fresh(["com.anthropic.claude"], announced: [:], now: now) == ["com.anthropic.claude"])
        let announced = ["com.anthropic.claude": now]
        #expect(PrivacyIndicator.fresh(["com.anthropic.claude"], announced: announced, now: now.addingTimeInterval(30)).isEmpty)
        #expect(PrivacyIndicator.fresh(["com.anthropic.claude", "camera"], announced: announced, now: now.addingTimeInterval(30)) == ["camera"])
        #expect(PrivacyIndicator.fresh(["com.anthropic.claude"], announced: announced, now: now.addingTimeInterval(16 * 60)) == ["com.anthropic.claude"])
    }

    @Test func aRankingSavedBeforeMeetingsFindsThemBesideTheirNeighbour() {
        let saved: [ActivitySource] = [.music, .privacy, .agents, .timers, .downloads, .scripts, .keepAwake]
        #expect(ActivitySource.completed(saved) == [.music, .privacy, .meetings, .agents, .timers, .downloads, .scripts, .keepAwake])
        #expect(ActivitySource.completed([]) == ActivitySource.allCases)
        #expect(ActivitySource.completed([.music]).first == .music)
        #expect(ActivitySource(activityID: "meeting") == .meetings)
        #expect(ActivitySource(activityID: "pomodoro") == .timers)
    }
}

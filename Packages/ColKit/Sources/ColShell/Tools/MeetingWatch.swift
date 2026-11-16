import AppKit
import ColCore
import EventKit
import Observation

/// The next meeting, counted down in the closed island a few minutes before it starts, in its calendar's colour. The
/// calendar is read when it changes, when the day changes and when the Mac wakes; between those, one wake-up for the
/// next moment the countdown changes, and none at all while the day holds no event.
@MainActor
@Observable
final class MeetingWatch {
    /// The meeting counted down to, for the Live page and its Join button.
    private(set) var current: CalendarModel.Event?
    @ObservationIgnored var post: ((Activity) -> Void)?
    @ObservationIgnored var remove: ((String) -> Void)?

    @ObservationIgnored private let calendar: CalendarModel
    @ObservationIgnored private var events: [CalendarModel.Event] = []
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var running = false

    init(calendar: CalendarModel) {
        self.calendar = calendar
    }

    private var lead: TimeInterval { TimeInterval(Preferences.meetingLeadMinutes * 60) }

    func start() {
        guard !running else { return }
        running = true
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
        ]
        reload()
    }

    func stop() {
        running = false
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers = []
        wake?.cancel()
        events = []
        if current != nil { current = nil }
        remove?("meeting")
    }

    /// The setting changed: start, stop, or count with the new lead.
    func preferencesChanged() {
        if Preferences.showsNextMeeting, calendar.isAuthorized || EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            if running { update() } else { start() }
        } else if running {
            stop()
        }
    }

    /// Reads the next day and a half of the calendar.
    func reload() {
        guard running else { return }
        events = calendar.upcomingEvents(hours: 36)
        update()
    }

    private func update() {
        wake?.cancel()
        let now = Date()
        let times = events.map { MeetingCountdown.Event(id: $0.id, start: $0.start, isAllDay: $0.isAllDay) }
        let shown = MeetingCountdown.current(in: times, now: now, lead: lead).flatMap { pick in events.first { $0.id == pick.id } }
        if shown != current { current = shown }
        if let shown {
            post?(activity(for: shown, now: now))
        } else {
            remove?("meeting")
        }
        guard let next = MeetingCountdown.nextChange(in: times, now: now, lead: lead) else { return }
        wake = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0.5)))
            guard !Task.isCancelled else { return }
            self?.update()
        }
    }

    private func activity(for event: CalendarModel.Event, now: Date) -> Activity {
        let tint = Self.rgba(event.color)
        let symbol: CompactItem = .symbol(event.meeting != nil ? "video.fill" : "calendar", tint: tint)
        let trailing: CompactItem = event.start <= now
            ? .text(String(localized: "Now", bundle: .module), tint: tint)
            : .countdown(ends: event.start, total: lead, tint: tint)
        return Activity(id: "meeting", priority: .standard, compact: CompactPresentation(leading: symbol, trailing: trailing), updated: event.start.addingTimeInterval(-lead))
    }

    /// A calendar's colour, brightened when it is too dark to read on the black island.
    static func rgba(_ color: NSColor) -> RGBA {
        let srgb = color.usingColorSpace(.sRGB) ?? .systemBlue
        return RGBA(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent)).readableOnBlack
    }

    /// For screenshots: a meeting stands in for the calendar, counted down beside the camera.
    func showDemo(_ event: CalendarModel.Event) {
        current = event
        post?(activity(for: event, now: Date()))
    }
}

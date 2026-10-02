import AppKit
import SwiftUI
import EventKit
import ColCore
import Observation

/// The next events of the day, read with EventKit. Access is asked for only when the user taps to connect.
@MainActor
@Observable
final class CalendarModel {
    struct Event: Identifiable, Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var color: NSColor
        var meeting: URL?
    }

    struct Reminder: Identifiable, Equatable {
        var id: String
        var title: String
        var due: Date?
        var color: NSColor
    }

    private(set) var events: [Event] = []
    private(set) var reminders: [Reminder] = []
    private(set) var status = EKEventStore.authorizationStatus(for: .event)
    private(set) var reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var observer: NSObjectProtocol?

    var isAuthorized: Bool { status == .fullAccess }
    var canAsk: Bool { status == .notDetermined }

    func connect() {
        let store = EKEventStore()
        self.store = store
        Task { @MainActor in
            _ = try? await store.requestFullAccessToEvents()
            self.status = EKEventStore.authorizationStatus(for: .event)
            self.refresh()
        }
    }

    var remindersAuthorized: Bool { reminderStatus == .fullAccess }
    var canAskReminders: Bool { reminderStatus == .notDetermined }

    func connectReminders() {
        let store = self.store ?? EKEventStore()
        self.store = store
        Task { @MainActor in
            _ = try? await store.requestFullAccessToReminders()
            self.reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            self.refresh()
        }
    }

    /// Ticks a reminder off, in Reminders itself.
    func complete(_ reminder: Reminder) {
        guard let store, let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        try? store.save(item, commit: true)
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { reminders.removeAll { $0.id == reminder.id } }
    }

    /// Reminders due today or late, without waiting on EventKit's asynchronous fetch in the caller.
    private func refreshReminders() {
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        guard remindersAuthorized, let store else { reminders = []; return }
        let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date())
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        store.fetchReminders(matching: predicate) { found in
            let items = (found ?? []).prefix(4).map { reminder in
                Reminder(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "",
                    due: reminder.dueDateComponents?.date,
                    color: reminder.calendar?.color ?? .systemOrange
                )
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.reminders = Array(items) }
            }
        }
    }

    /// Reads the rest of today and tomorrow morning; cheap enough to run each time the island opens.
    func refresh() {
        refreshReminders()
        status = EKEventStore.authorizationStatus(for: .event)
        if store == nil, isAuthorized || remindersAuthorized { store = EKEventStore() }
        if remindersAuthorized, reminders.isEmpty { refreshReminders() }
        guard isAuthorized else { return }
        guard let store else { return }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        let now = Date()
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!))!
        let predicate = store.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .prefix(4)
            .map { event in
                Event(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.color ?? .systemBlue,
                    meeting: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
                )
            }
    }

    func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}

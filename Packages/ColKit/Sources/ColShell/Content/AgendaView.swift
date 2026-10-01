import ColCore
import SwiftUI

/// The next events of the day, beside the clock.
struct AgendaView: View {
    let calendar: CalendarModel

    var body: some View {
        Group {
            if calendar.isAuthorized {
                if calendar.events.isEmpty && calendar.reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        Text("Nothing else today", bundle: .module)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        let eventCount = calendar.reminders.isEmpty ? 3 : 2
                        ForEach(calendar.events.prefix(eventCount)) { event in
                            EventRow(event: event)
                        }
                        ForEach(calendar.reminders.prefix(3 - min(calendar.events.count, eventCount))) { reminder in
                            ReminderRow(reminder: reminder) { calendar.complete(reminder) }
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                        if calendar.canAskReminders {
                            Button { calendar.connectReminders() } label: {
                                Label { Text("Show reminders too", bundle: .module) } icon: { Image(systemName: "checklist") }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Button {
                    if calendar.canAsk { calendar.connect() } else { calendar.openSettings() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.canAsk ? "Show my agenda" : "Calendar access is off", bundle: .module)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(calendar.canAsk ? "Your next events, right here." : "Allow it in System Settings.", bundle: .module)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.fill))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarModel.Event

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Group {
                    if event.isAllDay {
                        Text("All day", bundle: .module)
                    } else if event.start <= Date() {
                        Text("Now, until \(event.end.formatted(date: .omitted, time: .shortened))", bundle: .module)
                    } else {
                        Text(event.start.formatted(date: Calendar.current.isDateInToday(event.start) ? .omitted : .abbreviated, time: .shortened))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 4)
            if let meeting = event.meeting {
                Button {
                    NSWorkspace.shared.open(meeting)
                } label: {
                    Label { Text("Join", bundle: .module) } icon: { Image(systemName: "video.fill") }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(RGBA_green))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var RGBA_green: Color { Color(red: 0.2, green: 0.84, blue: 0.4) }
}

/// A reminder due today: tick the circle to complete it in Reminders.
private struct ReminderRow: View {
    let reminder: CalendarModel.Reminder
    let complete: () -> Void
    @State private var done = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.4)) { done = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { complete() }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(done ? Color(nsColor: reminder.color) : (hovering ? .white : Theme.secondaryText))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle())
            .onHover { hovering = $0 }
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(done ? Theme.secondaryText : .white)
                    .strikethrough(done)
                    .lineLimit(1)
                if let due = reminder.due, !Calendar.current.isDateInToday(due) || Calendar.current.component(.hour, from: due) != 0 {
                    Text(due.formatted(date: Calendar.current.isDateInToday(due) ? .omitted : .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(due < Date() ? RGBA.red.color : Theme.secondaryText)
                }
            }
        }
    }
}

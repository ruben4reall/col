import ColCore
import SwiftUI

/// Pomodoro as a widget: focus and breaks, today's count, and the controls.
struct PomodoroWidget: View {
    let pomodoro: PomodoroModel
    let width: WidgetWidth

    var body: some View {
        if Preferences.showsPomodoro {
            PomodoroCard(pomodoro: pomodoro, roomy: width == .full)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.fill))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Text("Pomodoro is off", bundle: .module)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                IslandChip(symbol: "arrow.forward", title: Text("Settings…", bundle: .module)) { SettingsWindow.shared.show(.glance) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The Pomodoro itself, in the Tools page's timer card or in its own widget. `roomy` is for a whole page: a larger
/// ring, Skip, and today's count beside the controls.
struct PomodoroCard: View {
    let pomodoro: PomodoroModel
    var roomy = false
    var header: AnyView?

    var body: some View {
        if let session = pomodoro.session {
            running(session)
        } else {
            idle
        }
    }

    private func running(_ session: Pomodoro) -> some View {
        let tint = PomodoroModel.tint(for: session.phase).color
        let ring: CGFloat = roomy ? 56 : 40
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: roomy ? 16 : 10) {
                ZStack {
                    Circle().stroke(tint.opacity(0.2), lineWidth: roomy ? 5 : 4)
                    Circle()
                        .trim(from: 0, to: session.countdown.fraction(at: context.date))
                        .stroke(tint, style: StrokeStyle(lineWidth: roomy ? 5 : 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: session.countdown.fraction(at: context.date))
                    Image(systemName: PomodoroModel.symbol(for: session.phase))
                        .font(.system(size: roomy ? 17 : 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: ring, height: ring)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.phase == .focus ? "Focus" : "Break", bundle: .module)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(Countdown.format(session.countdown.remaining(at: context.date)))
                        .font(.system(size: roomy ? 28 : 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText(countsDown: true))
                    HStack(spacing: 6) {
                        PomodoroButton(symbol: session.countdown.isPaused ? "play.fill" : "pause.fill") { pomodoro.togglePause() }
                        if roomy { PomodoroButton(symbol: "forward.end.fill") { pomodoro.skip() } }
                        PomodoroButton(symbol: "xmark") { pomodoro.stop() }
                    }
                }
                if roomy {
                    Spacer(minLength: 0)
                    today.padding(.trailing, 4)
                }
            }
            .padding(.horizontal, roomy ? 16 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var idle: some View {
        let plan = pomodoro.plan
        return VStack(alignment: .leading, spacing: 4) {
            if let header { header } else {
                Label { Text("Pomodoro", bundle: .module) } icon: { Image(systemName: "brain.head.profile.fill") }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("\(plan.focusMinutes) min focus", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 2)
            Text("then \(plan.breakMinutes) min break", bundle: .module)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            if !roomy, pomodoro.todayCount > 0 {
                Text("\(pomodoro.todayCount) today", bundle: .module)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PomodoroModel.focusTint.color)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { pomodoro.start() } label: {
                    Label { Text("Focus", bundle: .module) } icon: { Image(systemName: "play.fill") }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableStyle())
                Spacer(minLength: 0)
                if roomy { today }
            }
        }
        .padding(roomy ? 14 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Today's completed sessions, a dot each up to five, then the figure.
    @ViewBuilder private var today: some View {
        let count = pomodoro.todayCount
        if count > 0 {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 3) {
                    if count <= 5 {
                        ForEach(0..<count, id: \.self) { _ in
                            Circle().fill(PomodoroModel.focusTint.color).frame(width: 6, height: 6)
                        }
                    } else {
                        Text(verbatim: "\(count)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(PomodoroModel.focusTint.color)
                    }
                }
                Text("today", bundle: .module)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(count) completed today", bundle: .module))
        }
    }
}

private struct PomodoroButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(Theme.raisedFill))
        }
        .buttonStyle(PressableStyle())
    }
}

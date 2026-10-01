import AppKit
import IsletCore
import SwiftUI

/// The controls that appear while the pointer is on the prompter: restart, slower, play or pause, faster, close.
struct ControlBar: View {
    let state: PrompterState

    var body: some View {
        HStack(spacing: 4) {
            button("arrow.counterclockwise", help: "Restart", size: 12) { state.actions.restart() }
            button("minus", help: "Slower", size: 12) { state.actions.slower() }
                .disabled(state.mode == .voice || state.mode == .manual)
            Button(action: { state.actions.toggle() }) {
                Image(systemName: state.isRolling ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LinearGradient(colors: [StageTheme.accent, StageTheme.ember], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(state.isRolling ? "Pause" : "Play")
            button("plus", help: "Faster", size: 12) { state.actions.faster() }
                .disabled(state.mode == .voice || state.mode == .manual)
            button("xmark", help: "Close", size: 11) { state.actions.close() }
        }
        .padding(4)
        .background(Capsule().fill(Color(white: 0.13).opacity(0.94)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }

    private func button(_ symbol: String, help: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Circle().fill(StageTheme.fill))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Everything drawn over the text: the countdown, notes, the summary of a take, the controls.
struct PrompterOverlay: View {
    let state: PrompterState
    @AppStorage(PrompterPreferences.Key.stageLight) private var light = StageLight.accent.rawValue
    /// The floating and full screen prompters show the timer and the level over the text; the notch in a band above it.
    let showsStatusRow: Bool
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            if showsStatusRow {
                VStack {
                    StatusRow(state: state)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                    Spacer()
                }
            }
            center
            VStack {
                Spacer()
                if state.isHovering, state.summary == nil {
                    ControlBar(state: state)
                        .scaleEffect(scale)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            if let flash = state.flash {
                Text(flash)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(white: 0.16).opacity(0.95)))
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.15), value: state.isHovering)
        .animation(.easeInOut(duration: 0.2), value: state.flash)
    }

    private var stageLight: StageLight { StageLight(rawValue: light) ?? .accent }

    @ViewBuilder private var center: some View {
        switch state.phase {
        case .countdown(let number):
            Text(verbatim: "\(number)")
                .font(.system(size: 64 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [StageTheme.highlightColor(stageLight), StageTheme.lightEnds(stageLight)[1]], startPoint: .top, endPoint: .bottom))
                .contentTransition(.numericText(countsDown: true))
                .shadow(color: StageTheme.accent.opacity(0.6), radius: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.72))
                .animation(.spring(duration: 0.35), value: number)
        case .finished:
            if let summary = state.summary {
                SummaryCard(summary: summary, state: state)
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.8))
                    .transition(.opacity)
            }
        default:
            if let failure = state.failure {
                MessageCard(failure: failure, state: state)
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.78))
            } else if let status = state.status {
                Label(status, systemImage: "waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StageTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(white: 0.14)))
            }
        }
    }
}

/// Elapsed and remaining time on the left (unless turned off in Settings), the microphone or the pace on the right.
struct StatusRow: View {
    let state: PrompterState
    @AppStorage(PrompterPreferences.Key.showsTimer) private var showsTimer = true

    var body: some View {
        HStack {
            TimerLabel(state: state)
                .opacity(showsTimer ? 1 : 0)
            Spacer()
            LevelLabel(state: state)
        }
    }
}

/// One side of the camera row of the notch prompter: the time left of the camera, the voice right of it.
struct CameraWing: View {
    enum Side { case time, voice }
    let side: Side
    let state: PrompterState
    @AppStorage(PrompterPreferences.Key.showsTimer) private var showsTimer = true

    var body: some View {
        // A long take may outgrow its side: the time then keeps what has elapsed, the voice its meter.
        ViewThatFits(in: .horizontal) {
            label(compact: false)
            label(compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side == .time ? .leading : .trailing)
        .padding(side == .time ? .leading : .trailing, 12)
        .padding(side == .time ? .trailing : .leading, 6)
    }

    @ViewBuilder private func label(compact: Bool) -> some View {
        switch side {
        case .time: TimerLabel(state: state, compact: compact).opacity(showsTimer ? 1 : 0)
        case .voice: LevelLabel(state: state, compact: compact)
        }
    }
}

struct TimerLabel: View {
    let state: PrompterState
    var compact = false
    @AppStorage(PrompterPreferences.Key.stageLight) private var light = StageLight.accent.rawValue

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.isRolling ? StageTheme.lightEnds(StageLight(rawValue: light) ?? .accent)[0] : Color.white.opacity(0.35))
                .frame(width: 5, height: 5)
            Text(Pace.clock(state.elapsed))
                .foregroundStyle(Color.white.opacity(0.9))
            if !compact {
                Text(verbatim: "−" + Pace.clock(state.remaining))
                    .foregroundStyle(StageTheme.tertiaryText)
            }
        }
        .font(StageTheme.Font.figure)
        .fixedSize()
    }
}

struct LevelLabel: View {
    let state: PrompterState
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            if state.mode.listens {
                LevelMeter(level: state.isRolling ? state.level : 0, speaking: state.isSpeaking && state.isRolling)
            }
            if let pace = state.mode == .voice ? state.measuredPace : state.wordsPerMinute, state.mode != .manual, !compact || !state.mode.listens {
                Text("\(Int(pace.rounded())) wpm", bundle: .module)
                    .font(StageTheme.Font.figure)
                    .foregroundStyle(StageTheme.tertiaryText)
            }
        }
        .fixedSize()
    }
}

/// Four bars that rise with the voice, lit in the lamp colour while the reader speaks.
struct LevelMeter: View {
    let level: Float
    let speaking: Bool
    @AppStorage(PrompterPreferences.Key.stageLight) private var light = StageLight.accent.rawValue

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                let weights: [Float] = [0.6, 1, 0.8, 0.5]
                let height = 3 + CGFloat(min(1, level * weights[index] * 1.4)) * 9
                Capsule()
                    .fill(speaking ? AnyShapeStyle(LinearGradient(colors: StageTheme.lightEnds(StageLight(rawValue: light) ?? .accent).reversed(), startPoint: .bottom, endPoint: .top)) : AnyShapeStyle(Color.white.opacity(0.4)))
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

struct SummaryCard: View {
    let summary: TakeSummary
    let state: PrompterState
    @AppStorage(PrompterPreferences.Key.stageLight) private var light = StageLight.accent.rawValue

    var body: some View {
        VStack(spacing: 10) {
            Text("That's a take.", bundle: .module)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 18) {
                figure(Pace.clock(summary.duration), String(localized: "time", bundle: .module))
                figure("\(Int(summary.averageWordsPerMinute.rounded()))", String(localized: "words a minute", bundle: .module))
                figure("\(Int((summary.coverage * 100).rounded()))%", String(localized: "of the script", bundle: .module))
                if summary.fillers > 0 { figure("\(summary.fillers)", summary.fillers == 1 ? String(localized: "filler", bundle: .module) : String(localized: "fillers", bundle: .module)) }
            }
            HStack(spacing: 8) {
                Button { state.actions.restart() } label: { Text("Again", bundle: .module) }
                    .buttonStyle(PillButtonStyle(primary: true))
                // After a take read at another pace than the speed set: roll at the reader's own pace next time.
                if let pace = summary.suggestedPace(range: PrompterPreferences.minimumPace...PrompterPreferences.maximumPace),
                   abs(pace - state.wordsPerMinute) >= 5 {
                    Button { state.actions.usePace(pace) } label: { Text("Use \(Int(pace)) wpm", bundle: .module) }
                        .buttonStyle(PillButtonStyle(primary: false))
                        .help(String(localized: "Roll the script at the pace you just read at.", bundle: .module))
                }
                Button { state.actions.close() } label: { Text("Close", bundle: .module) }
                    .buttonStyle(PillButtonStyle(primary: false))
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(StageTheme.highlightColor(StageLight(rawValue: light) ?? .accent))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(StageTheme.secondaryText)
        }
    }
}

struct MessageCard: View {
    let failure: ListenerFailure
    let state: PrompterState

    var body: some View {
        VStack(spacing: 10) {
            Text(failure.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 8) {
                if let url = failure.settingsURL {
                    Button { state.actions.openSettings(url) } label: { Text("Open System Settings", bundle: .module) }
                        .buttonStyle(PillButtonStyle(primary: true))
                }
                Button { state.actions.useAutoScroll() } label: { Text("Use Auto Scroll", bundle: .module) }
                    .buttonStyle(PillButtonStyle(primary: false))
            }
        }
        .padding(16)
    }
}

struct PillButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(primary ? AnyShapeStyle(LinearGradient(colors: [StageTheme.accent, StageTheme.ember], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(StageTheme.raisedFill)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A hosting view that lets clicks and gestures through to the text, except on the controls it shows.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Returns the areas, in this view's coordinates, that take the pointer right now.
    var interactiveRects: () -> [NSRect] = { [] }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRects().contains(where: { $0.contains(local) }) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

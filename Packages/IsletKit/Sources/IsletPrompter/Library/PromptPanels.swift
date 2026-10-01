import IsletCore
import SwiftUI

/// The big round button in the corner of the script: prompt, then pause and play.
struct PlayButton: View {
    let app: PrompterCenter
    @State private var pressed = false

    var body: some View {
        let phase = app.prompter.state.phase
        let rolling = phase == .rolling || { if case .countdown = phase { return true } else { return false } }()
        Button { app.playPause() } label: {
            Image(systemName: rolling ? "pause.fill" : "play.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: rolling ? 0 : 2)
                .frame(width: 84, height: 84)
                .background(Circle().fill(LinearGradient(colors: [StageTheme.accent, StageTheme.ember], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                .shadow(color: StageTheme.accent.opacity(0.55), radius: 18, y: 6)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressStyle())
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!app.canPrompt)
        .opacity(app.canPrompt ? 1 : 0.45)
        .help(rolling ? String(localized: "Pause (⌘↩)", bundle: .module) : String(localized: "Play this script (⌘↩, or ⌃⌥⌘P from any app)", bundle: .module))
        .accessibilityLabel(rolling ? String(localized: "Pause", bundle: .module) : String(localized: "Play", bundle: .module))
    }
}

/// Presses in a little, like a real button.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Below the script: the speed, from tortoise to hare, and the switch that stops the script whenever you stop talking.
/// Voice Follow, chosen from the toolbar, takes the speed over: the script then moves with your words.
struct SpeedPanel: View {
    let document: ScriptDocument
    @Binding var pace: Double
    @Binding var mode: String
    let lastSummary: String

    private var waitsForVoice: Binding<Bool> {
        Binding(get: { ScrollMode(rawValue: mode)?.listens == true },
                set: { mode = $0 ? ScrollMode.pace.rawValue : ScrollMode.auto.rawValue })
    }

    var body: some View {
        let words = document.wordCount
        let voice = mode == ScrollMode.voice.rawValue
        let manual = mode == ScrollMode.manual.rawValue
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speed", bundle: .module)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle(isOn: waitsForVoice) {
                    Label(String(localized: "Pause when I stop talking", bundle: .module), systemImage: "waveform")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(StageTheme.accent)
                .disabled(voice || manual)
                .help(String(localized: "The script rolls at this speed while you speak and waits as soon as you stop. Your voice is heard on your Mac and never recorded.", bundle: .module))
            }
            HStack(spacing: 12) {
                Image(systemName: "tortoise.fill")
                    .foregroundStyle(.secondary)
                Slider(value: $pace, in: PrompterPreferences.minimumPace...PrompterPreferences.maximumPace)
                    .tint(StageTheme.accent)
                Image(systemName: "hare.fill")
                    .foregroundStyle(.secondary)
            }
            .disabled(voice || manual)
            .opacity(voice || manual ? 0.4 : 1)
            HStack(spacing: 12) {
                Text(voice
                     ? String(localized: "Follows your words · \(words) words", bundle: .module)
                     : manual
                     ? String(localized: "Moves only when you move it · \(words) words", bundle: .module)
                     : String(localized: "\(Int(pace.rounded())) words a minute · \(words) words · \(Pace.clock(Pace.readingTime(words: words, wordsPerMinute: pace)))", bundle: .module))
                if !voice && !manual {
                    FitMenu(words: words, pace: $pace)
                }
                Spacer()
                if !lastSummary.isEmpty {
                    Label {
                        Text("Last take: \(lastSummary)", bundle: .module)
                    } icon: {
                        Image(systemName: "record.circle").foregroundStyle(StageTheme.accent)
                    }
                }
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(StageTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// Sets the speed so the script lasts exactly a usual length: 30 seconds for a short, a minute, two for a pitch.
struct FitMenu: View {
    let words: Int
    @Binding var pace: Double

    var body: some View {
        let durations = Pace.fittingDurations(words: words, range: PrompterPreferences.minimumPace...PrompterPreferences.maximumPace)
        if !durations.isEmpty {
            Menu {
                ForEach(durations, id: \.self) { seconds in
                    Button(Self.label(seconds)) { pace = Pace.wordsPerMinute(toRead: words, in: seconds) }
                }
            } label: {
                Label(String(localized: "Fit in", bundle: .module), systemImage: "timer")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Sets the speed so the script lasts exactly this long.", bundle: .module))
        }
    }

    static func label(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

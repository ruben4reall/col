import IsletCore
import IsletPrompter
import SwiftUI

/// The prompter in a page of the island: the script that will roll, how long it lasts, and the button that rolls it
/// out of the notch. While a take runs elsewhere (floating or full screen), it shows the take and its controls.
struct PrompterWidget: View {
    let center: PrompterCenter
    let width: WidgetWidth
    @AppStorage(PrompterPreferences.Key.mode) private var mode = ScrollMode.pace.rawValue
    @AppStorage(PrompterPreferences.Key.placement) private var placement = PrompterPlacement.notch.rawValue
    @AppStorage(PrompterPreferences.Key.wordsPerMinute) private var pace = Pace.conversational

    var body: some View {
        if center.prompter.isActive {
            TakeView(center: center, compact: width == .half)
        } else if let script = center.store.selected {
            if width == .full { full(script) } else { half(script) }
        } else {
            empty
        }
    }

    private func full(_ script: ScriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ScriptGlyph(size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: script.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(verbatim: details(script))
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                PromptButton(size: 50) { center.promptSelected() }
                    .disabled(!center.canPrompt)
            }
            if !script.preview.isEmpty {
                Text(verbatim: script.preview)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(2)
                    .padding(.top, 10)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                IslandChip(symbol: "doc.text.fill", title: Text("Scripts", bundle: .module)) { center.showLibrary() }
                IslandChip(symbol: "doc.on.clipboard.fill", title: nil) { center.promptClipboard() }
                    .help(Text("Roll the text on the clipboard", bundle: .module))
                Spacer(minLength: 4)
                ModeMenu(mode: $mode)
                PlaceMenu(placement: $placement)
            }
        }
    }

    private func half(_ script: ScriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ScriptGlyph(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: script.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(verbatim: duration(script))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 6)
            HStack {
                IslandChip(symbol: "doc.text.fill", title: Text("Scripts", bundle: .module)) { center.showLibrary() }
                Spacer(minLength: 4)
                PromptButton(size: 40) { center.promptSelected() }
                    .disabled(!center.canPrompt)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            ScriptGlyph(size: 36)
            Text("No script yet", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            IslandChip(symbol: "square.and.pencil", title: Text("Write a Script", bundle: .module)) { center.showLibrary() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func details(_ script: ScriptDocument) -> String {
        let mode = ScrollMode(rawValue: mode) ?? .pace
        return [String(localized: "\(script.wordCount) words", bundle: .module), duration(script), mode.title].joined(separator: " · ")
    }

    private func duration(_ script: ScriptDocument) -> String {
        Pace.clock(Pace.readingTime(words: script.wordCount, wordsPerMinute: pace))
    }
}

/// The prompter's mark: lines of text under a camera, on the Mac's accent.
private struct ScriptGlyph: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "text.aligncenter")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(Theme.accent.gradient)
            )
            .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.2, y: size * 0.06)
    }
}

/// The round button that rolls the script out of the notch.
private struct PromptButton: View {
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.035)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Theme.accent.gradient)
                        .brightness(hovering ? 0.06 : 0)
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: Theme.accent.opacity(0.45), radius: 12, y: 4)
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(Text("Roll the script out of the notch (⌃⌥⌘P)", bundle: .module))
        .accessibilityLabel(Text("Play", bundle: .module))
    }
}

/// A small capsule button of the island.
struct IslandChip: View {
    let symbol: String
    /// Nil draws the symbol alone, in a circle.
    let title: Text?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Label { title } icon: { Image(systemName: symbol) }
                        .padding(.horizontal, 10)
                } else {
                    Image(systemName: symbol).frame(width: 26)
                }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(height: 26)
            .background(Capsule().fill(.white.opacity(hovering ? 0.16 : 0.1)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// How the script moves: Voice Pace, Voice Follow, Auto Scroll or Manual.
private struct ModeMenu: View {
    @Binding var mode: String

    var body: some View {
        let current = ScrollMode(rawValue: mode) ?? .pace
        Menu {
            ForEach(ScrollMode.allCases) { option in
                Button { mode = option.rawValue } label: {
                    Label(option.title, systemImage: option == current ? "checkmark" : option.symbol)
                }
            }
        } label: {
            ChipLabel(symbol: current.symbol, title: current.title)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("How the script moves", bundle: .module))
    }
}

/// Where the prompter appears: in the notch, floating, or across a whole screen.
private struct PlaceMenu: View {
    @Binding var placement: String

    var body: some View {
        let current = PrompterPlacement(rawValue: placement) ?? .notch
        Menu {
            ForEach(PrompterPlacement.allCases) { option in
                Button { placement = option.rawValue } label: {
                    Label(option.title, systemImage: option == current ? "checkmark" : option.symbol)
                }
            }
        } label: {
            ChipLabel(symbol: current.symbol, title: current.title)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Where the prompter appears", bundle: .module))
    }
}

/// A chip's face: a symbol, a short name, and the chevron of a menu.
private struct ChipLabel: View {
    let symbol: String
    let title: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(verbatim: title)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(.white.opacity(hovering ? 0.16 : 0.1)))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
    }
}

/// A take running in a floating or full screen prompter: its time, its progress, pause and stop.
private struct TakeView: View {
    let center: PrompterCenter
    let compact: Bool

    var body: some View {
        let state = center.prompter.state
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(state.isRolling ? Color.red : Color.orange).frame(width: 8, height: 8)
                Text(verbatim: state.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: Pace.clock(state.elapsed))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            ProgressView(value: min(max(state.progress, 0), 1))
                .tint(Theme.accent)
            HStack(spacing: compact ? 6 : 10) {
                ControlButton(symbol: state.isRolling ? "pause.fill" : "play.fill", size: 16) { center.prompter.toggle() }
                ControlButton(symbol: "backward.end.fill", size: 14) { center.prompter.restart() }
                Spacer(minLength: 0)
                ControlButton(symbol: "xmark", size: 13) { center.prompter.stop() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

extension PrompterPlacement {
    var symbol: String {
        switch self {
        case .notch: "macbook"
        case .floating: "rectangle.on.rectangle"
        case .fullScreen: "rectangle.inset.filled"
        }
    }
}

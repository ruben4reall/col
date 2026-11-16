import ColCore
import SwiftUI

extension WidgetKind {
    var title: LocalizedStringResource {
        let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
        return switch self {
        case .music: LocalizedStringResource("Music", bundle: bundle)
        case .lyrics: LocalizedStringResource("Lyrics", bundle: bundle)
        case .clock: LocalizedStringResource("Clock", bundle: bundle)
        case .agenda: LocalizedStringResource("Agenda", bundle: bundle)
        case .prompter: LocalizedStringResource("Prompter", bundle: bundle)
        case .ai: LocalizedStringResource("AI apps", bundle: bundle)
        case .shelf: LocalizedStringResource("Shelf", bundle: bundle)
        case .clipboard: LocalizedStringResource("Clipboard", bundle: bundle)
        case .tools: LocalizedStringResource("Tools", bundle: bundle)
        case .system: LocalizedStringResource("System", bundle: bundle)
        case .weather: LocalizedStringResource("Weather", bundle: bundle)
        case .devices: LocalizedStringResource("Devices", bundle: bundle)
        case .pomodoro: LocalizedStringResource("Pomodoro", bundle: bundle)
        }
    }

    var summary: LocalizedStringResource {
        let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
        return switch self {
        case .music: LocalizedStringResource("The player, while something plays", bundle: bundle)
        case .lyrics: LocalizedStringResource("The words of the song, as it plays", bundle: bundle)
        case .clock: LocalizedStringResource("The time and the date", bundle: bundle)
        case .agenda: LocalizedStringResource("Your next events and today’s reminders", bundle: bundle)
        case .prompter: LocalizedStringResource("Your script under the camera, at the pace of your voice", bundle: bundle)
        case .ai: LocalizedStringResource("Your AI apps and your models, at a glance", bundle: bundle)
        case .shelf: LocalizedStringResource("Files dropped on the notch, AirDrop", bundle: bundle)
        case .clipboard: LocalizedStringResource("Your recent copies", bundle: bundle)
        case .tools: LocalizedStringResource("Timer, colour picker, mirror", bundle: bundle)
        case .system: LocalizedStringResource("Processor, graphics, memory, disk, network", bundle: bundle)
        case .weather: LocalizedStringResource("Now, today’s high and low, the hours ahead", bundle: bundle)
        case .devices: LocalizedStringResource("Your mouse, keyboard and trackpad, with their battery", bundle: bundle)
        case .pomodoro: LocalizedStringResource("Focus and breaks, and today’s sessions", bundle: bundle)
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .lyrics: "quote.bubble.fill"
        case .clock: "clock.fill"
        case .agenda: "calendar"
        case .prompter: "text.aligncenter"
        case .ai: "sparkles"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .tools: "square.grid.2x2.fill"
        case .system: "gauge.with.dots.needle.67percent"
        case .weather: "cloud.sun.fill"
        case .devices: "magicmouse.fill"
        case .pomodoro: "brain.head.profile.fill"
        }
    }

    var tint: Color {
        switch self {
        case .music: .pink
        case .lyrics: Color(red: 0.98, green: 0.24, blue: 0.4)
        case .clock: .gray
        case .agenda: .red
        case .prompter: .orange
        case .ai: Color(red: 0.36, green: 0.42, blue: 1)
        case .shelf: .blue
        case .clipboard: .orange
        case .tools: .teal
        case .system: .green
        case .weather: .cyan
        case .devices: .gray
        case .pomodoro: .red
        }
    }
}

/// A page of the open island: one stack of widgets across it, or two side by side. Each stack shows its first widget
/// that has something to show, and changes with a soft cross-fade when that changes.
struct PageView: View {
    let page: PageLayout
    let services: IslandServices

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(page.stacks.enumerated()), id: \.offset) { _, stack in
                StackView(stack: stack, width: page.width, services: services)
            }
        }
    }
}

private struct StackView: View {
    let stack: WidgetStack
    let width: WidgetWidth
    let services: IslandServices

    var body: some View {
        let shown = stack.shown { WidgetAvailability.hasContent($0, services: services) }
        ZStack {
            if let shown {
                WidgetView(kind: shown, width: width, services: services)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .id(shown)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: shown)
    }
}

/// Whether a widget has something to show now.
@MainActor
enum WidgetAvailability {
    static func hasContent(_ kind: WidgetKind, services: IslandServices) -> Bool {
        switch kind {
        case .music: services.media.hasPlayer
        case .lyrics: services.media.hasPlayer && services.lyrics.lyrics != nil
        case .devices: !services.glance.accessories.levels.isEmpty
        case .clock, .agenda, .prompter, .ai, .shelf, .clipboard, .tools, .system, .weather, .pomodoro: true
        }
    }
}

/// One widget at the width its page gives it.
struct WidgetView: View {
    let kind: WidgetKind
    let width: WidgetWidth
    let services: IslandServices

    var body: some View {
        switch kind {
        case .music:
            if width == .full {
                MediaPlayerView(media: services.media, audio: services.audio)
            } else {
                CompactPlayerView(media: services.media)
            }
        case .lyrics:
            LyricsView(lyrics: services.lyrics, media: services.media, width: width)
        case .clock:
            ClockView()
        case .agenda:
            AgendaView(calendar: services.calendar)
        case .prompter:
            PrompterWidget(center: .shared, width: width)
        case .ai:
            AIWidget(ai: services.ai, agents: services.agents, navigation: services.navigation, width: width)
        case .shelf:
            ShelfPage(shelf: services.shelf)
        case .clipboard:
            ClipboardPage(clipboard: services.clipboard)
        case .tools:
            ToolsPage(timer: services.timer, picker: services.picker, mirror: services.mirror, awake: services.awake, pomodoro: services.glance.pomodoro)
        case .system:
            SystemPage(stats: services.stats)
        case .weather:
            WeatherWidget(weather: services.glance.weather, width: width)
        case .devices:
            DevicesWidget(accessories: services.glance.accessories, width: width)
        case .pomodoro:
            PomodoroWidget(pomodoro: services.glance.pomodoro, width: width)
        }
    }
}

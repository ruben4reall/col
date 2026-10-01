import IsletCore
import SwiftUI

extension WidgetKind {
    var title: LocalizedStringResource {
        let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
        return switch self {
        case .music: LocalizedStringResource("Music", bundle: bundle)
        case .clock: LocalizedStringResource("Clock", bundle: bundle)
        case .agenda: LocalizedStringResource("Agenda", bundle: bundle)
        case .shelf: LocalizedStringResource("Shelf", bundle: bundle)
        case .clipboard: LocalizedStringResource("Clipboard", bundle: bundle)
        case .tools: LocalizedStringResource("Tools", bundle: bundle)
        case .system: LocalizedStringResource("System", bundle: bundle)
        }
    }

    var summary: LocalizedStringResource {
        let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
        return switch self {
        case .music: LocalizedStringResource("The player, while something plays", bundle: bundle)
        case .clock: LocalizedStringResource("The time and the date", bundle: bundle)
        case .agenda: LocalizedStringResource("Your next events and today’s reminders", bundle: bundle)
        case .shelf: LocalizedStringResource("Files dropped on the notch, AirDrop", bundle: bundle)
        case .clipboard: LocalizedStringResource("Your recent copies", bundle: bundle)
        case .tools: LocalizedStringResource("Timer, colour picker, mirror", bundle: bundle)
        case .system: LocalizedStringResource("Processor, memory, disk, network", bundle: bundle)
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .clock: "clock.fill"
        case .agenda: "calendar"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .tools: "square.grid.2x2.fill"
        case .system: "gauge.with.dots.needle.67percent"
        }
    }

    var tint: Color {
        switch self {
        case .music: .pink
        case .clock: .gray
        case .agenda: .red
        case .shelf: .blue
        case .clipboard: .orange
        case .tools: Theme.coral.color
        case .system: .green
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
        case .clock, .agenda, .shelf, .clipboard, .tools, .system: true
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
        case .clock:
            ClockView()
        case .agenda:
            AgendaView(calendar: services.calendar)
        case .shelf:
            ShelfPage(shelf: services.shelf)
        case .clipboard:
            ClipboardPage(clipboard: services.clipboard)
        case .tools:
            ToolsPage(timer: services.timer, picker: services.picker, mirror: services.mirror, awake: services.awake)
        case .system:
            SystemPage(stats: services.stats)
        }
    }
}

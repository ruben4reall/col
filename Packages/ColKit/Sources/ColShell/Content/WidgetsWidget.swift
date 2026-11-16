import ColCore
import SwiftUI

/// The Widgets place: the widgets programs and devices pushed, and those read from an address, as tiles. Half a page
/// shows one at a time, the whole page two; dots under them go to the others. Addresses are read while it shows.
struct WidgetsWidget: View {
    let center: WidgetCenter
    let width: WidgetWidth
    @State private var page = 0

    var body: some View {
        let entries = center.entries
        let perPage = width == .full ? 2 : 1
        let pages = max(1, Int((Double(entries.count) / Double(perPage)).rounded(.up)))
        let shown = Array(entries.dropFirst(min(page, pages - 1) * perPage).prefix(perPage))
        Group {
            if entries.isEmpty {
                empty
            } else if let confirming = center.confirming, entries.contains(where: { $0.id == confirming.widget }) {
                CallConfirmation(button: confirming.button) { center.confirm() } cancel: { center.cancelConfirmation() }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        ForEach(shown) { entry in
                            // One widget across a whole page lays its lines and buttons beside its figure.
                            WidgetTile(entry: entry, center: center, wide: width == .full && shown.count == 1)
                        }
                    }
                    if pages > 1 { dots(pages) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { center.watch() }
        .onDisappear { center.unwatch() }
    }

    private func dots(_ count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { page = index }
                } label: {
                    Circle()
                        .fill(index == min(page, count - 1) ? Color.white : Theme.tertiaryText)
                        .frame(width: 6, height: 6)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text("No widgets yet", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Push one with colctl widget set, from a device paired with Col Connect, or read one from an address in Settings, Connect.", bundle: .module)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One widget: its symbol and title, its figure, a bar for its progress, its lines and its buttons. Stale figures dim
/// and say when they arrived.
struct WidgetTile: View {
    let entry: WidgetCenter.Entry
    let center: WidgetCenter?
    var wide = false
    @State private var armed = false

    var body: some View {
        // Checked again every half minute while the tile shows, so old figures dim as they age.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let stale = entry.widget.isStale(updated: entry.updated, now: context.date)
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 16) {
                        figure(stale: stale, now: context.date)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            lines(limit: 3)
                            Spacer(minLength: 0)
                            buttons
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        figure(stale: stale, now: context.date)
                        lines(limit: (entry.widget.buttons?.isEmpty ?? true) ? 3 : 1)
                        Spacer(minLength: 0)
                        buttons
                    }
                }
            }
            .opacity(stale ? 0.55 : 1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.fill))
    }

    private var tint: Color { entry.widget.resolvedTint.color }

    private func figure(stale: Bool, now: Date) -> some View {
        let widget = entry.widget
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: widget.symbol ?? "square.grid.2x2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(verbatim: widget.title ?? widget.id)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if stale || entry.error != nil {
                    Image(systemName: entry.error != nil ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.error != nil ? Color.orange : Theme.tertiaryText)
                        .help(Text(verbatim: entry.error ?? ""))
                }
            }
            if let value = widget.value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value)
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if let unit = widget.unit {
                        Text(verbatim: unit)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else if entry.isWaiting {
                Text(entry.error ?? String(localized: "Reading…", bundle: .module))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.error == nil ? Theme.secondaryText : Color.orange)
                    .lineLimit(2)
            }
            if let progress = widget.progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(tint).frame(width: max(4, geometry.size.width * progress))
                    }
                }
                .frame(height: 4)
                .animation(.spring(duration: 0.4, bounce: 0), value: progress)
            }
            if stale, !entry.isWaiting {
                Text(entry.updated, format: .relative(presentation: .named))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    @ViewBuilder private func lines(limit: Int) -> some View {
        if let lines = entry.widget.lines, !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.prefix(limit).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        if let buttons = entry.widget.buttons, !buttons.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    WidgetCallButton(button: button, state: center?.calls[WidgetCenter.callKey(entry.id, button)]) {
                        center?.press(button, of: entry.id)
                    }
                    .disabled(!armed)
                }
            }
            // A widget that arrives or changes under the pointer waits a moment before its buttons answer a click.
            .task(id: ArmedFor(id: entry.id, updated: entry.updated)) {
                armed = false
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled { armed = true }
            }
        }
    }

    private struct ArmedFor: Equatable {
        var id: String
        var updated: Date
    }
}

private struct WidgetCallButton: View {
    let button: WidgetButton
    let state: WidgetCenter.Call?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                switch state {
                case .calling: ProgressView().controlSize(.mini).tint(.white)
                case .done: Image(systemName: "checkmark").foregroundStyle(RGBA.green.color)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case nil: if let symbol = button.symbol { Image(systemName: symbol) }
                }
                Text(verbatim: button.title).lineLimit(1)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.2 : 0.13)))
        }
        .buttonStyle(PressableStyle())
        .disabled(state == .calling)
        .onHover { hovering = $0 }
        .help(Text(verbatim: button.resolvedMethod + " " + button.url))
    }
}

/// The first press of a button: the address it calls, whole, and whether to call it. Said yes to once, it is called
/// at once from then on.
private struct CallConfirmation: View {
    let button: WidgetButton
    let confirm: () -> Void
    let cancel: () -> Void
    /// Call It waits a moment after the question appears, so the click that pressed the button never answers it.
    @State private var armed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("“\(button.title)” calls an address for the first time", bundle: .module)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            // The host on its own, where a long address cannot hide it, then the whole address.
            if let host = button.host {
                Text(verbatim: host)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(verbatim: button.resolvedMethod + " " + button.url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            HStack(spacing: 8) {
                Button(action: confirm) {
                    Text("Call It", bundle: .module)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableStyle())
                .disabled(!armed)
                .opacity(armed ? 1 : 0.5)
                Button(action: cancel) {
                    Text("Cancel", bundle: .module)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.13)))
                }
                .buttonStyle(PressableStyle())
                Spacer(minLength: 0)
                Text("Asked once for this button", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.orange.opacity(0.1))
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { armed = true }
        }
    }
}

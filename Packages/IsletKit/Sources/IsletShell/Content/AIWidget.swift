import IsletCore
import SwiftUI

/// The AI apps of the Mac in a page of the island: their icons, bright when open, a tap opens one; the model servers
/// with the model they hold and whether it is generating; and the agents at work, a tap away.
struct AIWidget: View {
    let ai: AIAppsModel
    let agents: AgentCenter
    let navigation: IslandNavigation
    let width: WidgetWidth

    var body: some View {
        Group {
            if ai.installed.isEmpty && ai.servers.isEmpty {
                empty
            } else if width == .full {
                HStack(alignment: .top, spacing: 16) {
                    apps(limit: 4, size: 40)
                        .frame(width: 200, alignment: .leading)
                    status
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    apps(limit: 3, size: 34)
                    statusLine
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { ai.watch() }
        .onDisappear { ai.unwatch() }
    }

    /// Open apps first, then the others, dimmer, each with its name, as many as the place holds.
    private func apps(limit: Int, size: CGFloat) -> some View {
        let ordered = ai.installed.sorted { ai.running.contains($0.id) && !ai.running.contains($1.id) }
        return HStack(alignment: .top, spacing: 6) {
            ForEach(ordered.prefix(limit), id: \.id) { app in
                AppIconButton(app: app, icon: ai.icon(for: app), open: ai.running.contains(app.id), size: size) { ai.open(app) }
            }
        }
    }

    /// Agents at work and the model servers, the right column of a wide page.
    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentsLine(agents: agents) { navigation.show(.live) }
            ForEach(Array(ai.servers.prefix(2)), id: \.id) { server in
                ServerRow(server: server, status: ai.statuses[server.id], compact: false)
            }
            if ai.servers.isEmpty {
                IslandChip(symbol: "plus", title: Text("Add Your AI", bundle: .module)) {
                    SettingsWindow.shared.show(.aiApps)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line for half a page: the first server, else the agents.
    @ViewBuilder private var statusLine: some View {
        if let server = ai.servers.first {
            ServerRow(server: server, status: ai.statuses[server.id], compact: true)
        } else {
            AgentsLine(agents: agents) { navigation.show(.live) }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color(red: 0.45, green: 0.5, blue: 1))
            Text("No AI app on this Mac", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Claude, ChatGPT, Ollama, LM Studio and others show here once installed.", bundle: .module)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The coding agents at work, in a line that opens the Live page.
private struct AgentsLine: View {
    let agents: AgentCenter
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: agents.sessions.isEmpty ? "sparkles" : "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(agents.sessions.isEmpty ? Theme.tertiaryText : Theme.coral.color)
                    .symbolEffect(.pulse, isActive: !agents.sessions.isEmpty)
                Group {
                    if agents.sessions.isEmpty {
                        Text("No agent at work", bundle: .module)
                    } else {
                        Text("\(agents.sessions.count) agent sessions", bundle: .module)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(agents.sessions.isEmpty ? Theme.secondaryText : .white)
                Spacer(minLength: 0)
                if !agents.pending.isEmpty {
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).fill(Theme.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// An app's own icon; open, it is bright with a dot beneath, like the Dock.
private struct AppIconButton: View {
    let app: AIApp
    let icon: NSImage?
    let open: Bool
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "sparkles").font(.system(size: size * 0.45)).foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
                .opacity(open ? 1 : 0.5)
                .scaleEffect(hovering ? 1.08 : 1)
                Text(verbatim: app.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(open ? .white : Theme.tertiaryText)
                    .lineLimit(1)
                    .frame(width: size + 10)
                Circle()
                    .fill(.white.opacity(open ? 0.85 : 0))
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: hovering)
        .help(Text(verbatim: app.name))
    }
}

/// A model server: whether it answers, the model in memory, and whether it is generating.
private struct ServerRow: View {
    let server: ModelServer
    let status: ModelServerStatus?
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.7), radius: status?.generating == true ? 4 : 0)
            Text(verbatim: server.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                // The name says which machine: it keeps its room, the model's name gives way.
                .layoutPriority(1)
            Text(verbatim: detail)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if status?.generating == true, !compact {
                Text("Generating", bundle: .module)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(Color(red: 0.2, green: 0.84, blue: 0.4)))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).fill(Theme.fill))
    }

    private var color: Color {
        guard let status else { return .gray }
        if !status.reachable { return Color(red: 1, green: 0.27, blue: 0.23) }
        return status.loaded.isEmpty ? .white.opacity(0.5) : Color(red: 0.2, green: 0.84, blue: 0.4)
    }

    private var detail: String {
        guard let status else { return String(localized: "Checking…", bundle: .module) }
        guard status.reachable else { return String(localized: "Not answering", bundle: .module) }
        if let model = status.loaded.first {
            let memory = model.memory.map { " · " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? ""
            return model.name + memory
        }
        return String(localized: "\(status.models.count) models, none loaded", bundle: .module)
    }
}

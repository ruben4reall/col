import ColCore
import SwiftUI

/// The AI apps of the Mac in a page of the island: their icons, bright when open, a tap opens one; the model servers
/// with the model they hold and whether it is generating; and the agents at work, a tap away.
struct AIWidget: View {
    let ai: AIAppsModel
    let agents: AgentCenter
    let navigation: IslandNavigation
    let width: WidgetWidth

    var body: some View {
        // The models that can answer now, for the field at the foot of a wide page.
        let choices = ai.ask.choices(servers: ai.servers, statuses: ai.statuses)
        Group {
            if ai.installed.isEmpty && ai.servers.isEmpty {
                empty
            } else if width == .full, !ai.ask.messages.isEmpty {
                AskConversation(ai: ai, choices: choices)
            } else if width == .full {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {
                        apps(limit: 4, size: 40)
                            .frame(width: 200, alignment: .leading)
                        // The field takes a line of the island's height: the column keeps two lines then.
                        status(lines: choices.isEmpty ? 3 : 2)
                    }
                    Spacer(minLength: 0)
                    if !choices.isEmpty { AskBar(ai: ai, choices: choices) }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    apps(limit: 3, size: 34)
                    statusLine
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            ai.watch()
            ai.ask.resolve(choices)
        }
        .onChange(of: choices) {
            ai.ask.resolve(choices)
            ai.ask.askOnLaunch()
        }
        .onDisappear { ai.unwatch() }
    }

    /// Open apps first, then the others, dimmer, each with its name, as many as the place holds.
    private func apps(limit: Int, size: CGFloat) -> some View {
        let ordered = ai.installed.sorted { ai.running.contains($0.id) && !ai.running.contains($1.id) }
        return HStack(alignment: .top, spacing: 6) {
            ForEach(ordered.prefix(limit), id: \.id) { app in
                AppIconButton(app: app, open: ai.running.contains(app.id), size: size) { ai.open(app) }
            }
        }
    }

    /// Agents at work and the model servers, the right column of a wide page, in as many lines as it has: the agents'
    /// line gives way to a server while no agent works and room is short.
    private func status(lines: Int) -> some View {
        let showsAgents = !agents.sessions.isEmpty || lines > 2 || ai.servers.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            if showsAgents { AgentsLine(agents: agents) { navigation.show(.live) } }
            ForEach(Array(ai.servers.prefix(lines - (showsAgents ? 1 : 0))), id: \.id) { server in
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

/// The coding agents at work, in a line that opens the Live page: their apps' icons, overlapping as in a group.
private struct AgentsLine: View {
    let agents: AgentCenter
    let open: () -> Void

    /// One icon per agent at work, the busiest first.
    private var icons: [AppIcon] {
        var seen: [AppIcon] = []
        for session in agents.sessions {
            let icon = CodingAgent.icon(for: session.agent)
            if !seen.contains(icon) { seen.append(icon) }
        }
        return Array(seen.prefix(3))
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                if icons.isEmpty {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                } else {
                    // The busiest on top, the others tucked behind it.
                    HStack(spacing: -5) {
                        ForEach(Array(icons.enumerated()), id: \.element) { index, icon in
                            AppIconView(icon: icon, size: 20).zIndex(Double(icons.count - index))
                        }
                    }
                }
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
    let open: Bool
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                AppIconView(icon: app.icon, size: size)
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
            // The server's app, with a light in its corner: green with a model loaded, red when it does not answer.
            AppIconView(icon: AppIcon(bundleIdentifiers: server.kind.icon.bundleIdentifiers, name: server.kind.icon.name, mark: server.kind.icon.mark,
                                      symbol: server.isLocal ? "desktopcomputer" : "network", tint: server.kind.icon.tint), size: 20)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .background(Circle().stroke(Color.black, lineWidth: 2.5))
                        .shadow(color: color.opacity(0.7), radius: status?.generating == true ? 4 : 0)
                        .offset(x: 1, y: 1)
                }
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
                // Dots that type, as in Messages: short enough to leave the model's name its room.
                PulsingDots(color: .black, dot: 3.5, spacing: 2.5)
                    .frame(width: 26, height: 18)
                    .background(Capsule().fill(Color(red: 0.2, green: 0.84, blue: 0.4)))
                    .accessibilityLabel(Text("Generating", bundle: .module))
                    .help(Text("Generating", bundle: .module))
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

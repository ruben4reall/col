import AppKit
import IsletCore
import SwiftUI

/// The AI apps Islet works with, each with its own icon when it is on this Mac.
struct AIAppsPane: View {
    @State private var shows = Preferences.showsAgents

    var body: some View {
        PaneScaffold(pane: .aiApps) {
            Section {
                IconToggle(symbol: "sparkles", tint: SettingsPane.aiApps.tint, title: "Show AI apps in the notch",
                           detail: "A sign beside the camera while one works, and the island opens when one needs you.", isOn: $shows)
                    .onChange(of: shows) { Preferences.showsAgents = shows }
            }
            Section {
                ForEach(CodingAgent.allCases, id: \.self) { agent in
                    AIAppRow(agent: agent)
                }
            } header: {
                Text("Connected through their hooks", bundle: .module)
            } footer: {
                Text("Islet never signs in to any AI service: it only hears the hooks each app calls on your Mac. Connecting adds Islet’s hooks to the app’s settings and keeps a backup next to them. VS Code keeps Copilot permissions according to each session’s mode; other apps and scripts can report with islet agent.", bundle: .module)
            }
        }
    }
}

/// One AI app: its icon, what Islet does with it, and whether it reports to Islet.
private struct AIAppRow: View {
    let agent: CodingAgent
    @State private var connected = false
    @State private var installed = true
    @State private var message: String?

    var body: some View {
        HStack(spacing: 12) {
            AppIconTile(icon: AIAppIcons.icon(for: agent), symbol: CodingAgent.symbol(for: agent.name), tint: AIAppIcons.tint(for: agent))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(agent.name)
                    if connected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.small)
                    }
                }
                Text(message ?? capabilities)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if installed || connected {
                Button {
                    message = connected ? CommandLineInstaller.disconnect(agent) : CommandLineInstaller.connect(agent)
                    connected = CommandLineInstaller.isConnected(agent)
                } label: {
                    Text(connected ? "Disconnect" : "Connect", bundle: .module)
                }
            } else {
                Text("Not on this Mac", bundle: .module).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            connected = CommandLineInstaller.isConnected(agent)
            installed = CommandLineInstaller.isInstalled(agent)
        }
    }

    private var capabilities: String {
        agent.answersPermissions
            ? String(localized: "Sessions in the notch, and permission requests with Allow and Deny.", bundle: .module)
            : String(localized: "Sessions in the notch; you answer permission requests in the app.", bundle: .module)
    }
}

/// The icon of the app behind each AI tool, read from the app itself when it is installed: Islet ships no logos.
@MainActor
enum AIAppIcons {
    private static var cache: [CodingAgent: NSImage?] = [:]

    static func icon(for agent: CodingAgent) -> NSImage? {
        if let cached = cache[agent] { return cached }
        let icon = bundleIdentifiers(for: agent)
            .lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[agent] = icon
        return icon
    }

    /// The desktop app that carries each tool's icon.
    static func bundleIdentifiers(for agent: CodingAgent) -> [String] {
        switch agent {
        case .claude: ["com.anthropic.claudefordesktop"]
        case .codex: ["com.openai.codex", "com.openai.chat"]
        case .gemini: []
        case .cursor: ["com.todesktop.230313mzl4w4u92"]
        case .copilot: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        }
    }

    static func tint(for agent: CodingAgent) -> Color {
        switch agent {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.2, green: 0.2, blue: 0.22)
        case .gemini: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .cursor: Color(red: 0.12, green: 0.12, blue: 0.14)
        case .copilot: Color(red: 0.0, green: 0.47, blue: 0.83)
        }
    }
}

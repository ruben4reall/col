import AppKit
import ColCore
import SwiftUI

/// Everything that thinks, in one pane: the AI apps found on this Mac with their own icons, the coding agents that
/// report through their hooks, and the model servers, the Mac's own and those added by the user.
struct AIAppsPane: View {
    @State private var shows = Preferences.showsAgents
    @State private var adding = false
    private var ai: AIAppsModel? { IslandController.shared?.aiApps }

    var body: some View {
        PaneScaffold(pane: .aiApps) {
            Section {
                IconToggle(symbol: "sparkles", tint: SettingsPane.aiApps.tint, title: "Show AI apps in the notch",
                           detail: "A sign beside the camera while one works, and the island opens when one needs you.", isOn: $shows)
                    .onChange(of: shows) { Preferences.showsAgents = shows }
            }
            if let ai {
                Section {
                    if ai.installed.isEmpty {
                        Text("No AI app found on this Mac yet. Claude, ChatGPT, Gemini, Perplexity, Cursor, Ollama, LM Studio and many others show here once installed.", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(ai.installed, id: \.id) { app in
                        InstalledAppRow(app: app, open: ai.running.contains(app.id)) { ai.open(app) }
                    }
                } header: {
                    Text("On this Mac", bundle: .module)
                } footer: {
                    Text("Recognized by their identifiers and shown with their own icons. Logos belong to their owners.", bundle: .module)
                }
            }
            Section {
                ForEach(CodingAgent.allCases, id: \.self) { agent in
                    AgentRow(agent: agent)
                }
            } header: {
                Text("Coding agents", bundle: .module)
            } footer: {
                Text("Col never signs in to any AI service: it only hears the hooks each app calls on your Mac. Connecting adds Col’s hooks to the app’s settings and keeps a backup next to them. VS Code keeps Copilot permissions according to each session’s mode; other apps and scripts can report with colctl agent.", bundle: .module)
            }
            if let ai {
                Section {
                    ForEach(ai.servers, id: \.id) { server in
                        ServerSettingsRow(server: server, status: ai.statuses[server.id], removable: Preferences.aiServers.contains { $0.id == server.id }) {
                            ai.remove(server)
                        }
                    }
                    Button { adding = true } label: {
                        Label { Text("Add Your AI…", bundle: .module) } icon: { Image(systemName: "plus.circle.fill") }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Your AI", bundle: .module)
                } footer: {
                    Text("A model server on this Mac or on another machine of your network: Ollama, LM Studio, llama.cpp or any OpenAI-compatible server. Col shows whether it answers, the model it holds and, when the server can tell, whether it is generating. Tokens are kept in your Keychain.", bundle: .module)
                }
                .onAppear {
                    ai.refreshInstalled()
                    ai.watch()
                }
                .onDisappear { ai.unwatch() }
                .sheet(isPresented: $adding) {
                    AddServerSheet { server, token in ai.add(server, token: token) }
                }
            }
        }
    }
}

private struct InstalledAppRow: View {
    let app: AIApp
    let open: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconTile(icon: app.icon)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: app.name)
                    if open {
                        Text("Running", bundle: .module)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                }
                Text(role).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(action: action) { Text(open ? "Show" : "Open", bundle: .module) }
        }
        .padding(.vertical, 1)
    }

    private var role: LocalizedStringResource {
        if app.server != nil { return LocalizedStringResource("Runs models on this Mac: its server shows under Your AI.", bundle: .settings) }
        if let agent = app.agent { return LocalizedStringResource("Its agent, \(agent.name), connects below.", bundle: .settings) }
        return switch app.role {
        case .assistant: LocalizedStringResource("An AI assistant: open it from the island.", bundle: .settings)
        case .coding: LocalizedStringResource("A code editor with AI: open it from the island.", bundle: .settings)
        case .models: LocalizedStringResource("Runs models on this Mac.", bundle: .settings)
        }
    }
}

/// One coding agent: whether it is on this Mac, whether it reports to Col, and the button to change that.
private struct AgentRow: View {
    let agent: CodingAgent
    @State private var connected = false
    @State private var installed = true
    @State private var message: String?

    var body: some View {
        HStack(spacing: 12) {
            AppIconTile(icon: agent.icon)
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

/// A model server in the settings: what it is, where, and what it said last.
private struct ServerSettingsRow: View {
    let server: ModelServer
    let status: ModelServerStatus?
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // The icon of the app that serves it, Ollama or LM Studio, else where it runs.
            AppIconTile(icon: AppIcon(bundleIdentifiers: server.kind.icon.bundleIdentifiers, name: server.kind.icon.name, mark: server.kind.icon.mark,
                                      symbol: server.isLocal ? "desktopcomputer" : "network",
                                      tint: server.isLocal ? RGBA(red: 0.56, green: 0.56, blue: 0.58) : .blue))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: server.name)
                    Text(verbatim: server.kind.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                Text(verbatim: summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Circle().fill(color).frame(width: 8, height: 8)
            if removable {
                Button(role: .destructive, action: remove) { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                    .buttonStyle(.borderless)
                    .help(Text("Remove", bundle: .module))
            }
        }
    }

    private var color: Color {
        guard let status else { return .gray }
        return status.reachable ? .green : .red
    }

    private var summary: String {
        let address = server.address.host.map { $0 + (server.address.port.map { ":\($0)" } ?? "") } ?? server.address.absoluteString
        guard let status else { return address }
        guard status.reachable else { return address + " · " + String(localized: "Not answering", bundle: .module) }
        let loaded = status.loaded.first.map { String(localized: "\($0.name) loaded", bundle: .module) }
            ?? String(localized: "\(status.models.count) models, none loaded", bundle: .module)
        return address + " · " + loaded
    }
}

/// Adds a server: a name, an address, a token if it needs one. Col finds out what kind of server it is.
private struct AddServerSheet: View {
    let add: (ModelServer, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var token = ""
    @State private var testing = false
    @State private var found: (kind: ModelServerKind, models: [String])?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "sparkles", tint: SettingsPane.aiApps.tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Your AI", bundle: .module).font(.system(size: 17, weight: .bold))
                    Text("A model server on this Mac or another machine of your network.", bundle: .module).foregroundStyle(.secondary)
                }
            }
            Form {
                TextField(text: $name, prompt: Text("Studio PC", bundle: .module)) { Text("Name", bundle: .module) }
                TextField(text: $address, prompt: Text(verbatim: "192.168.1.20:11434")) { Text("Address", bundle: .module) }
                    .onChange(of: address) { found = nil; failed = false }
                SecureField(text: $token, prompt: Text("Only if the server asks for one", bundle: .module)) { Text("Token", bundle: .module) }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 150)
            Group {
                if let found {
                    Label {
                        Text("\(found.kind.name) answers, with \(found.models.count) models.", bundle: .module)
                    } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                } else if failed {
                    Label {
                        Text("Nothing answers at this address. Check that the server listens on your network, not only on its own machine.", bundle: .module)
                    } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                } else {
                    Text("Ollama listens on port 11434, LM Studio on 1234, llama.cpp on 8080.", bundle: .module).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if testing { ProgressView().controlSize(.small) }
                Button { test() } label: { Text("Test", bundle: .module) }
                    .disabled(ModelServer.address(from: address, kind: nil) == nil || testing)
                Button {
                    guard let found, let url = ModelServer.address(from: address, kind: found.kind) else { return }
                    let title = name.trimmingCharacters(in: .whitespaces)
                    add(ModelServer(name: title.isEmpty ? (url.host ?? found.kind.name) : title, kind: found.kind, address: url, usesToken: !token.isEmpty), token)
                    dismiss()
                } label: { Text("Add", bundle: .module) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(found == nil)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    /// Tries the address as typed, then with each kind's usual port when none was given.
    private func test() {
        testing = true
        found = nil
        failed = false
        let typed = address
        let secret = token.isEmpty ? nil : token
        Task { @MainActor in
            defer { testing = false }
            let candidates: [URL] = typed.contains(":") && !typed.hasSuffix(":")
                ? [ModelServer.address(from: typed, kind: nil)].compactMap { $0 }
                : ModelServerKind.allCases.compactMap { ModelServer.address(from: typed, kind: $0) }
            for url in candidates {
                if let kind = await ModelServerClient.shared.detect(url, token: secret) {
                    let status = await ModelServerClient.shared.status(of: ModelServer(name: "", kind: kind, address: url, usesToken: secret != nil), token: secret)
                    address = url.absoluteString
                    found = (kind, status.models)
                    return
                }
            }
            failed = true
        }
    }
}

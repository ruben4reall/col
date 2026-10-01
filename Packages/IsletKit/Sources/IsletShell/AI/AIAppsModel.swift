import AppKit
import IsletCore
import Observation

/// Everything that thinks on this Mac: the AI apps installed and open, and the model servers, the Mac's own (Ollama,
/// LM Studio when installed) and those the user added, on this Mac or another machine. Apps are followed through the
/// system's launch and quit notices; servers are asked every few seconds, only while something shows them.
@MainActor
@Observable
final class AIAppsModel {
    /// The catalog's apps installed on this Mac, in the catalog's order.
    private(set) var installed: [AIApp] = []
    /// The ids of the installed apps that are open now.
    private(set) var running: Set<String> = []
    private(set) var servers: [ModelServer] = []
    private(set) var statuses: [String: ModelServerStatus] = [:]
    /// The conversation with one of these servers, from the island.
    let ask = AskSession()

    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        refreshInstalled()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let identifier = app.bundleIdentifier, AICatalog.app(bundleIdentifier: identifier) != nil
                else { return }
                MainActor.assumeIsolated { self?.refreshRunning() }
            })
        }
    }

    /// The installed apps, looked up again: after an app was installed or removed, and when the settings open.
    func refreshInstalled() {
        AppIcons.forget()
        installed = AICatalog.apps.filter { AppIcons.url(for: $0.icon) != nil }
        refreshServers()
        refreshRunning()
    }

    private func refreshRunning() {
        let open = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        running = Set(installed.filter { app in app.bundleIdentifiers.contains(where: open.contains) }.map(\.id))
    }

    /// The Mac's own servers, for the model apps installed, then the user's.
    func refreshServers() {
        var servers: [ModelServer] = []
        for app in installed {
            guard let kind = app.server, let address = URL(string: "http://localhost:\(kind.defaultPort)") else { continue }
            servers.append(ModelServer(id: "local-\(kind.rawValue)", name: app.name, kind: kind, address: address))
        }
        self.servers = servers + Preferences.aiServers
        statuses = statuses.filter { id, _ in self.servers.contains { $0.id == id } }
    }

    /// Opens the app, the copy named as the app when several share its identifier.
    func open(_ app: AIApp) {
        guard let url = AppIcons.url(for: app.icon) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Servers

    /// Views that show the servers say when they appear and go: servers are only asked while one does.
    func watch() {
        watchers += 1
        guard poll == nil else { return }
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkServers()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        poll?.cancel()
        poll = nil
    }

    func checkServers() async {
        for server in servers {
            let token = server.usesToken ? Keychain.token(for: server.id) : nil
            let status = await ModelServerClient.shared.status(of: server, token: token)
            if statuses[server.id] != status { statuses[server.id] = status }
        }
    }

    func add(_ server: ModelServer, token: String?) {
        Keychain.setToken(token, for: server.id)
        Preferences.aiServers = Preferences.aiServers.filter { $0.id != server.id } + [server]
        refreshServers()
        Task { await checkServers() }
    }

    func remove(_ server: ModelServer) {
        Keychain.setToken(nil, for: server.id)
        Preferences.aiServers = Preferences.aiServers.filter { $0.id != server.id }
        refreshServers()
    }

    /// Something to show in the island: an AI app open, or a server that answers.
    var hasContent: Bool {
        !running.isEmpty || statuses.values.contains { $0.reachable }
    }
}

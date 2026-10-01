import AppKit
import ColCore

/// The routes of the local socket, and the `col://` links, both turning requests into live activities.
///
///     GET    /v1/status
///     GET    /v1/activities
///     POST   /v1/activities                 body: ActivityRequest
///     POST   /v1/activities/<id>/done       ?text=Done
///     DELETE /v1/activities/<id>
///     POST   /v1/agents/events?agent=codex  body: a hook event as the agent wrote it (claude by default, codex,
///                                           gemini, cursor); answers {"decision": allow|deny|ask}
@MainActor
final class ControlAPI {
    let server = ControlServer()
    private let custom: CustomActivities
    private let agents: AgentCenter
    private let post: (Activity) -> Void
    private let remove: (String) -> Void

    init(custom: CustomActivities, agents: AgentCenter, post: @escaping (Activity) -> Void, remove: @escaping (String) -> Void) {
        self.custom = custom
        self.agents = agents
        self.post = post
        self.remove = remove
    }

    func start() {
        server.route = { [weak self] request, respond in
            guard let self else { return respond(.error("unavailable", status: 503)) }
            self.handle(request, respond)
        }
        try? server.start()
    }

    func stop() {
        server.stop()
    }

    private func handle(_ request: HTTPRequest, _ respond: @escaping ControlServer.Respond) {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.first == "v1" else { return respond(.error("not found", status: 404)) }
        let route = Array(parts.dropFirst())
        // The id of /v1/activities/<id>[/done].
        let id = route.count >= 2 && route[0] == "activities" ? route[1] : ""
        switch (request.method, route) {
        case ("GET", ["status"]):
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            respond(.json(["app": "Col", "version": version, "activities": custom.entries.count, "agents": agents.sessions.count]))

        case ("GET", ["activities"]):
            let list = custom.entries.map { entry -> [String: Any] in
                var item: [String: Any] = ["id": entry.id, "finished": entry.finished]
                if let title = entry.request.title { item["title"] = title }
                if let progress = entry.request.progress { item["progress"] = progress }
                if let text = entry.request.text { item["text"] = text }
                return item
            }
            respond(.json(["activities": list]))

        case ("POST", ["activities"]):
            do {
                let payload = try JSONDecoder().decode(ActivityRequest.self, from: request.body).validated()
                push(payload)
                respond(.json(["id": payload.id]))
            } catch {
                respond(.error("expected an activity with an id", status: 400))
            }

        case ("POST", ["activities", id, "done"]) where !id.isEmpty:
            guard finish(id, text: request.query["text"]) else { return respond(.error("no such activity", status: 404)) }
            respond(.json(["id": id]))

        case ("DELETE", ["activities", id]) where !id.isEmpty:
            custom.remove(id)
            remove("api." + id)
            respond(.json(["id": id]))

        case ("POST", ["agents", "events"]):
            guard let agent = CodingAgent(rawValue: request.query["agent"] ?? "claude"),
                  let raw = try? JSONDecoder().decode([String: JSONValue].self, from: request.body)
            else { return respond(.error("expected a hook event", status: 400)) }
            // Events an agent sends that Col does not follow are simply acknowledged.
            guard let event = agent.event(from: raw) else { return respond(.json(["decision": "ask"])) }
            agents.receive(event) { decision in respond(.json(["decision": decision.rawValue])) }

        default:
            respond(.error("not found", status: 404))
        }
    }

    func push(_ request: ActivityRequest) {
        custom.upsert(request)
        post(request.activity(now: Date()))
    }

    @discardableResult
    func finish(_ id: String, text: String?) -> Bool {
        guard let entry = custom.finish(id, text: text) else { return false }
        let request = entry.request
        post(Activity(
            id: request.boardID,
            priority: .transient,
            compact: CompactPresentation(
                leading: .symbol(request.symbol ?? "circle.hexagongrid.fill", tint: request.resolvedTint),
                trailing: .symbol("checkmark.circle.fill", tint: .green)
            ),
            expires: entry.expires,
            updated: Date()
        ))
        return true
    }

    /// `col://push?id=build&title=Build&progress=0.4`, `col://done?id=build`, `col://remove?id=build`, and
    /// `col://settings?pane=developers`, `col://welcome`. Links written for Islet, `islet://…`, work the same.
    func open(_ url: URL) {
        guard ["col", "islet"].contains(url.scheme), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        var query: [String: String] = [:]
        components.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
        let action = url.host ?? ""
        switch action {
        case "settings":
            SettingsWindow.shared.show(query["pane"].flatMap(SettingsPane.init(link:)) ?? .general)
            return
        case "welcome":
            WelcomeWindow.shared.show()
            return
        default:
            break
        }
        guard let id = query["id"], !id.isEmpty else { return }
        switch action {
        case "push":
            let request = ActivityRequest(
                id: id, title: query["title"], subtitle: query["subtitle"], symbol: query["symbol"], tint: query["tint"],
                progress: query["progress"].flatMap(Double.init), text: query["text"], priority: query["priority"],
                ttl: query["ttl"].flatMap(Double.init)
            )
            if let valid = try? request.validated() { push(valid) }
        case "done":
            finish(id, text: query["text"])
        case "remove":
            custom.remove(id)
            remove("api." + id)
        default:
            break
        }
    }
}

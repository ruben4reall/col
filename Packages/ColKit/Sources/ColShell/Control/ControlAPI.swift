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
///                                           gemini, cursor); answers {"decision": allow|deny|ask}, with the
///                                           `updatedInput` an answered question or an approved plan hands back
///     GET    /v1/widgets
///     PUT    /v1/widgets/<id>               body: WidgetRequest (docs/widgets.md)
///     DELETE /v1/widgets/<id>
///     POST   /v1/extensions/reload
///
/// Col Connect reaches some of the same routes from the network (`connect`), never the agents'.
@MainActor
final class ControlAPI {
    let server = ControlServer()
    private let custom: CustomActivities
    private let agents: AgentCenter
    private let widgets: WidgetCenter
    private let post: (Activity) -> Void
    private let remove: (String) -> Void
    /// Opens the island, on a page when one is named, or closes it: `col://open?page=live`, `col://close`.
    var showIsland: ((_ open: Bool, _ page: String?) -> Void)?
    /// Reads the extensions folder again, after `colctl extensions install` or `remove`; answers how many there are.
    var reloadExtensions: (() -> Int)?

    init(custom: CustomActivities, agents: AgentCenter, widgets: WidgetCenter, post: @escaping (Activity) -> Void, remove: @escaping (String) -> Void) {
        self.custom = custom
        self.agents = agents
        self.widgets = widgets
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
        // The id of /v1/widgets/<id>.
        let widgetID = route.count == 2 && route[0] == "widgets" ? route[1] : ""
        switch (request.method, route) {
        case ("GET", ["status"]):
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            respond(.json([
                "app": "Col", "version": version, "activities": custom.entries.count, "agents": agents.sessions.count,
                "widgets": widgets.count, "connect": Preferences.connectEnabled,
            ]))

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
                guard push(payload) else { return respond(.error(Self.activitiesFull, status: 409)) }
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
            // Where the session runs, as `colctl hook` found it, to bring its terminal forward later.
            let origin = AgentOrigin(query: request.query, folder: event.cwd)
            agents.receive(event, origin: origin) { answer in respond(.json(answer.json)) }

        case ("GET", ["widgets"]):
            let list = widgets.entries.map { entry -> [String: Any] in
                var item: [String: Any] = ["id": entry.id, "fromURL": entry.fromURL]
                if let title = entry.widget.title { item["title"] = title }
                if let value = entry.widget.shownValue { item["value"] = value }
                if !entry.isWaiting { item["updated"] = ISO8601DateFormatter().string(from: entry.updated) }
                return item
            }
            respond(.json(["widgets": list]))

        case ("PUT", ["widgets", widgetID]) where !widgetID.isEmpty, ("POST", ["widgets", widgetID]) where !widgetID.isEmpty:
            let (status, body) = setWidget(widgetID, body: request.body)
            respond(.json(body, status: status))

        case ("DELETE", ["widgets", widgetID]) where !widgetID.isEmpty:
            widgets.remove(widgetID)
            respond(.json(["id": widgetID]))

        case ("POST", ["extensions", "reload"]):
            respond(.json(["extensions": reloadExtensions?() ?? 0]))

        default:
            respond(.error("not found", status: 404))
        }
    }

    /// Sets the widget a body describes under the id of its address, which wins over the body's: the status and the
    /// JSON to answer.
    func setWidget(_ id: String, body: Data) -> (Int, [String: Any]) {
        guard var widget = try? JSONDecoder().decode(WidgetRequest.self, from: body.isEmpty ? Data("{}".utf8) : body) else {
            return (400, ["error": "expected a widget as JSON (docs/widgets.md)"])
        }
        widget.id = id
        do {
            let valid = try widget.validated()
            guard widgets.set(valid) else {
                return (409, ["error": "the island holds \(WidgetCenter.maximumPushed) pushed widgets at most: remove one first"])
            }
            return (200, ["id": valid.id])
        } catch let invalid as WidgetRequest.Invalid {
            return (400, ["error": invalid.message])
        } catch {
            return (400, ["error": "invalid widget"])
        }
    }

    /// A request a device paired with Col Connect made, on a route ConnectRoute allows: the same as the local API's.
    func connect(_ route: ConnectRoute, _ request: ConnectRequest) -> ConnectResponse {
        switch route {
        case .status:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            return .json(["app": "Col", "version": version, "activities": custom.entries.count, "widgets": widgets.count])
        case .pushActivity:
            guard let payload = try? JSONDecoder().decode(ActivityRequest.self, from: request.body).validated() else {
                return .error("expected an activity with an id", status: 400)
            }
            guard push(payload) else { return .error(Self.activitiesFull, status: 409) }
            return .json(["id": payload.id])
        case .finishActivity(let id):
            guard finish(id, text: request.query["text"]) else { return .error("no such activity", status: 404) }
            return .json(["id": id])
        case .removeActivity(let id):
            custom.remove(id)
            remove("api." + id)
            return .json(["id": id])
        case .setWidget(let id):
            let (status, body) = setWidget(id, body: request.body)
            return .json(body, status: status)
        case .removeWidget(let id):
            widgets.remove(id)
            return .json(["id": id])
        }
    }

    static let activitiesFull = "Col holds \(CustomActivities.maximum) activities pushed by programs at most: remove one, or let one end"

    /// Shows or updates an activity; false when as many run as Col holds and this one is new.
    @discardableResult
    func push(_ request: ActivityRequest) -> Bool {
        guard custom.upsert(request) else { return false }
        post(request.activity(now: Date()))
        return true
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

    /// `col://push?id=build&title=Build&progress=0.4`, `col://done?id=build`, `col://remove?id=build`,
    /// `col://open?page=live`, `col://close`, `col://settings?pane=developers` and `col://welcome`. Links written for
    /// Islet, `islet://…`, work the same.
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
        case "open", "close":
            showIsland?(action == "open", query["page"])
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

import Foundation

/// A coding agent's hook event, in the shape Claude Code and Codex write on a hook's stdin. Other agents' events are
/// translated into it by `CodingAgent.event(from:)`.
public struct HookEvent: Decodable, Sendable, Equatable {
    public var sessionID: String
    public var event: String
    public var cwd: String?
    public var toolName: String?
    public var toolInput: [String: JSONValue]?
    public var notificationType: String?
    public var message: String?
    /// Set by agents without hooks, through `islet agent`: their name stands for the project.
    public var agentName: String?
    /// The agent whose hooks sent the event. Not part of the payload: the hook says it in the request.
    public var agent: CodingAgent? = nil

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case event = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case notificationType = "notification_type"
        case message
        case agentName = "agent_name"
    }

    public init(sessionID: String, event: String, cwd: String? = nil, toolName: String? = nil, toolInput: [String: JSONValue]? = nil, notificationType: String? = nil, message: String? = nil, agentName: String? = nil, agent: CodingAgent? = nil) {
        self.agentName = agentName
        self.agent = agent
        self.sessionID = sessionID
        self.event = event
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
        self.notificationType = notificationType
        self.message = message
    }

    /// The project, named after the folder the session runs in.
    public var project: String {
        if let agentName, !agentName.isEmpty { return agentName }
        guard let cwd, !cwd.isEmpty else { return agent?.name ?? "Agent" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Tool names across agents, shown the way people read them.
    static let toolLabels = [
        "run_shell_command": "Shell", "shell": "Shell", "write_file": "Write", "replace": "Edit", "read_file": "Read",
        "read_many_files": "Read", "web_fetch": "Fetch", "google_web_search": "Search", "search_file_content": "Grep",
        "list_directory": "List", "apply_patch": "Patch",
    ]

    /// A short line saying what the tool is about to do: the command for a shell, the file for edits.
    public var toolSummary: String? {
        guard let toolName else { return nil }
        let input = toolInput ?? [:]
        func file(_ key: String) -> String? {
            input[key]?.string.map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        func firstLine(_ key: String) -> String? {
            input[key]?.string.map { $0.split(separator: "\n").first.map(String.init) ?? $0 }
        }
        let detail: String? = switch toolName {
        case "Bash", "Shell", "run_shell_command", "shell":
            input["description"]?.string ?? firstLine("command")
        case "Edit", "Write", "Read", "NotebookEdit", "MultiEdit":
            file("file_path") ?? file("notebook_path")
        case "Grep", "Glob":
            input["pattern"]?.string
        case "WebFetch", "web_fetch":
            input["url"]?.string.flatMap { URL(string: $0)?.host } ?? input["prompt"]?.string
        case "WebSearch", "google_web_search":
            input["query"]?.string
        case "Agent", "Task":
            input["description"]?.string
        default:
            // Other agents' tools: the first argument that reads like a target.
            firstLine("command") ?? file("file_path") ?? file("absolute_path") ?? file("path") ?? input["pattern"]?.string
                ?? input["query"]?.string
        }
        let label = Self.toolLabels[toolName] ?? toolName
        guard let detail, !detail.isEmpty else { return label }
        return "\(label) · \(String(detail.prefix(70)))"
    }

    /// The command itself, for a permission request that needs the full picture.
    public var toolDetail: String? {
        guard let input = toolInput else { return nil }
        return input["command"]?.string ?? input["file_path"]?.string ?? input["absolute_path"]?.string ?? input["url"]?.string
    }
}

/// Any JSON value, to carry tool inputs without knowing their shape.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

/// One coding agent session, followed through its hooks.
public struct AgentSession: Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable {
        case idle
        case working(String?)
        /// Waiting for the user: a permission, or an answer.
        case waiting(String?)
        case done
    }

    public var id: String
    public var project: String
    /// The agent's name when it came through its hooks, shown beside the project.
    public var agent: String?
    public var state: State
    public var since: Date
    public var updated: Date
}

/// Every agent session and what each is doing.
public struct AgentBoard: Sendable, Equatable {
    public private(set) var sessions: [String: AgentSession] = [:]

    public init() {}

    public mutating func apply(_ event: HookEvent, at now: Date) {
        var session = sessions[event.sessionID]
            ?? AgentSession(id: event.sessionID, project: event.project, state: .idle, since: now, updated: now)
        session.project = event.project
        if let agent = event.agent { session.agent = agent.name }
        let previous = session.state
        switch event.event {
        case "SessionStart":
            session.state = .idle
        case "UserPromptSubmit":
            // Never the prompt itself: the island can be on a shared screen.
            session.state = .working(nil)
        case "PreToolUse", "PostToolUse", "PostToolUseFailure", "SubagentStart":
            session.state = .working(event.toolSummary ?? current(previous))
        case "PermissionRequest":
            session.state = .waiting(event.toolSummary)
        case "Notification":
            if ["permission_prompt", "idle_prompt", "agent_needs_input", "elicitation_dialog"].contains(event.notificationType ?? "") {
                // A permission prompt already shown with its details keeps them.
                if case .waiting = previous, event.notificationType == "permission_prompt" { break }
                session.state = .waiting(event.message)
            }
        case "Stop":
            session.state = .done
        case "SessionEnd", "End":
            sessions[event.sessionID] = nil
            return
        // Generic states, from `islet agent` for agents without hooks.
        case "Working":
            session.state = .working(event.message)
        case "Waiting":
            session.state = .waiting(event.message)
        case "Done":
            session.state = .done
        case "Idle":
            session.state = .idle
        default:
            break
        }
        if !Self.sameKind(previous, session.state) { session.since = now }
        session.updated = now
        sessions[event.sessionID] = session
    }

    private func current(_ state: AgentSession.State) -> String? {
        if case .working(let detail) = state { return detail }
        return nil
    }

    private static func sameKind(_ a: AgentSession.State, _ b: AgentSession.State) -> Bool {
        switch (a, b) {
        case (.idle, .idle), (.working, .working), (.waiting, .waiting), (.done, .done): true
        default: false
        }
    }

    /// Sessions that have finished long enough ago go quiet.
    public mutating func settle(now: Date, after interval: TimeInterval = 6) {
        for (id, session) in sessions where session.state == .done && now.timeIntervalSince(session.updated) >= interval {
            if CodingAgent.named(session.agent)?.endsSessions == false {
                // No end will ever come for this session: it leaves with its Done.
                sessions[id] = nil
            } else {
                sessions[id]?.state = .idle
            }
        }
    }

    public mutating func forget(_ id: String) {
        sessions[id] = nil
    }

    /// Sessions, the ones that need the user first, then the busy ones, then by recency.
    public var ordered: [AgentSession] {
        sessions.values.sorted {
            (Self.rank($0.state), $0.updated, $0.id) > (Self.rank($1.state), $1.updated, $1.id)
        }
    }

    private static func rank(_ state: AgentSession.State) -> Int {
        switch state {
        case .waiting: 3
        case .working: 2
        case .done: 1
        case .idle: 0
        }
    }

    /// What the notch shows for all agents together, or nil when none is doing anything worth showing.
    public func activity(now: Date, tint: RGBA) -> Activity? {
        let active = ordered.filter { $0.state != .idle }
        guard let top = active.first else { return nil }
        let count = active.count
        let leading: CompactItem = .symbol(CodingAgent.symbol(for: top.agent), tint: tint)
        switch top.state {
        case .waiting:
            return Activity(
                id: "agents",
                priority: .alert,
                compact: CompactPresentation(leading: leading, trailing: .symbol("hand.raised.fill", tint: .orange)),
                updated: top.updated
            )
        case .working:
            return Activity(
                id: "agents",
                priority: .standard,
                compact: CompactPresentation(leading: leading, trailing: count > 1 ? .text("\(count)", tint: tint) : .spinner(tint: tint)),
                updated: top.since
            )
        case .done:
            return Activity(
                id: "agents",
                priority: .transient,
                compact: CompactPresentation(leading: leading, trailing: .symbol("checkmark.circle.fill", tint: .green)),
                expires: top.updated.addingTimeInterval(4),
                updated: top.updated
            )
        case .idle:
            return nil
        }
    }
}

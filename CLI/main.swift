// colctl: pushes live activities to Col, and connects coding agents to it.
//
// Talks HTTP over Col's Unix socket, so it only reaches the Col of the user running it.

import Foundation

let usage = """
usage: colctl <command> [options]

  push <id> [--title T] [--subtitle S] [--symbol SF_SYMBOL] [--tint COLOR]
            [--progress 0..1 | N%] [--text T] [--priority ambient|standard|alert] [--ttl SECONDS]
                        show or update a live activity in the notch
  done <id> [--text T]  mark an activity done: a check mark, then it leaves
  remove <id>           take an activity away
  list                  list the activities pushed by programs
  status                check that Col is running

  hooks install [--agent AGENT] [--settings PATH]
                        connect a coding agent to the notch; AGENT is claude (default),
                        codex, gemini, cursor, copilot or all
  hooks uninstall [--agent AGENT] [--settings PATH]
  hooks status          show which agents are connected
  hook [--agent AGENT]  the hook itself: reads the agent's event on stdin
  agent <name> <working|waiting|done|idle|end> [--message M] [--session S]
                        report any other agent or script (Aider, OpenCode...) to the notch

Colours: white, green, orange, red, blue, purple, yellow, pink, teal, gray, or #RRGGBB.
Example: colctl push build --title Build --symbol hammer.fill --tint orange --progress 40%
"""

// MARK: Socket

func socketPath() -> String {
    if let path = ProcessInfo.processInfo.environment["COL_SOCKET"], !path.isEmpty { return path }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Col/col.sock").path
}

enum ClientError: Error {
    case notRunning
    case failed(String)
}

/// Sends one HTTP request over the socket and returns the status and body.
func request(_ method: String, _ path: String, body: Data? = nil, timeout: Int = 5) throws -> (Int, Data) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ClientError.notRunning }
    defer { close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socketPath().utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ClientError.notRunning }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in bytes.withUnsafeBytes { buffer.copyMemory(from: $0) } }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else { throw ClientError.notRunning }
    var wait = timeval(tv_sec: timeout, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
    var noSigPipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

    let payload = body ?? Data()
    var message = Data("\(method) \(path) HTTP/1.1\r\nHost: col\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
    message.append(payload)
    let sent = message.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
    guard sent == message.count else { throw ClientError.notRunning }

    var response = Data()
    var chunk = [UInt8](repeating: 0, count: 16_384)
    while true {
        let count = recv(fd, &chunk, chunk.count, 0)
        if count <= 0 { break }
        response.append(chunk, count: count)
    }
    guard let split = response.range(of: Data("\r\n\r\n".utf8)),
          let head = String(data: response[..<split.lowerBound], encoding: .utf8),
          let status = head.split(separator: " ").dropFirst().first.flatMap({ Int($0) })
    else { throw ClientError.failed("no answer from Col") }
    return (status, Data(response[split.upperBound...]))
}

func json(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("colctl: \(message)\n".utf8))
    exit(1)
}

func run(_ method: String, _ path: String, body: Data? = nil) -> Data {
    do {
        let (status, data) = try request(method, path, body: body)
        guard status == 200 else {
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            fail(reason ?? "Col answered \(status)")
        }
        return data
    } catch ClientError.notRunning {
        fail("Col is not running")
    } catch {
        fail("\(error)")
    }
}

// MARK: Options

func options(_ arguments: ArraySlice<String>) -> [String: String] {
    var result: [String: String] = [:]
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        guard argument.hasPrefix("--") else { fail("unexpected argument \(argument)") }
        guard let value = iterator.next() else { fail("\(argument) needs a value") }
        result[String(argument.dropFirst(2))] = value
    }
    return result
}

func percentOrFraction(_ value: String) -> Double? {
    if value.hasSuffix("%") { return Double(value.dropLast()).map { $0 / 100 } }
    guard let number = Double(value) else { return nil }
    return number > 1 ? number / 100 : number
}

// MARK: Hooks

/// The coding agents Col connects to, where each keeps its hooks, and the events Col follows.
struct Agent {
    enum Format { case claude, gemini, cursor, vscode }

    let id: String
    let name: String
    let settings: String
    let format: Format
    /// Event, whether it takes a tool matcher, timeout in seconds.
    let events: [(name: String, matcher: Bool, timeout: Int)]
    /// Hooks that wait for the user's answer in the island.
    var answersPermissions: Bool { id == "claude" || id == "codex" }

    static let all: [Agent] = [
        Agent(id: "claude", name: "Claude Code", settings: "~/.claude/settings.json", format: .claude, events: [
            ("SessionStart", false, 5), ("UserPromptSubmit", false, 5), ("PreToolUse", true, 5), ("PostToolUse", true, 5),
            ("PermissionRequest", true, 120), ("Notification", false, 5), ("Stop", false, 5), ("SessionEnd", false, 2),
        ]),
        Agent(id: "codex", name: "Codex", settings: "~/.codex/hooks.json", format: .claude, events: [
            ("SessionStart", false, 5), ("UserPromptSubmit", false, 5), ("PreToolUse", false, 5), ("PostToolUse", false, 5),
            ("PermissionRequest", false, 120), ("Stop", false, 5), ("SessionEnd", false, 2),
        ]),
        Agent(id: "gemini", name: "Gemini CLI", settings: "~/.gemini/settings.json", format: .gemini, events: [
            ("SessionStart", false, 5), ("BeforeAgent", false, 5), ("BeforeTool", true, 5), ("AfterTool", true, 5),
            ("AfterAgent", false, 5), ("Notification", false, 5), ("SessionEnd", false, 2),
        ]),
        Agent(id: "cursor", name: "Cursor", settings: "~/.cursor/hooks.json", format: .cursor, events: [
            ("sessionStart", false, 5), ("beforeSubmitPrompt", false, 5), ("postToolUse", false, 5),
            ("afterShellExecution", false, 5), ("afterFileEdit", false, 5), ("stop", false, 5), ("sessionEnd", false, 2),
        ]),
        Agent(id: "copilot", name: "GitHub Copilot (VS Code)", settings: "~/.copilot/hooks/col.json", format: .vscode, events: [
            ("SessionStart", false, 5), ("UserPromptSubmit", false, 5), ("PreToolUse", false, 5),
            ("PostToolUse", false, 5), ("Stop", false, 5),
        ]),
    ]

    static func named(_ id: String) -> Agent? { all.first { $0.id == id } }

    var command: String { id == "claude" ? "\"$HOME/.local/bin/colctl\" hook" : "\"$HOME/.local/bin/colctl\" hook --agent \(id)" }
}

/// Forwards one hook event. Never gets in the agent's way: when Col is not running, or anything goes wrong, it
/// answers what "carry on as usual" means for that agent and exits 0.
func hook(_ agent: Agent) -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let event = (try? JSONSerialization.jsonObject(with: input) as? [String: Any]) ?? [:]
    let name = event["hook_event_name"] as? String ?? ""
    // Gemini CLI and Cursor read a JSON answer from every hook; Cursor's prompt hook must let the prompt through.
    let neutral: String? = switch agent.format {
    case .claude: nil
    case .gemini: "{}"
    case .cursor: name == "beforeSubmitPrompt" ? #"{"continue":true}"# : "{}"
    case .vscode: name == "PreToolUse" ? "{}" : nil
    }
    func carryOn() -> Never {
        if let neutral { FileHandle.standardOutput.write(Data(neutral.utf8)) }
        exit(0)
    }
    guard !event.isEmpty else { carryOn() }
    let waits = agent.answersPermissions && name == "PermissionRequest"
    guard let (status, data) = try? request("POST", "/v1/agents/events?agent=\(agent.id)", body: input, timeout: waits ? 110 : 3),
          status == 200, waits,
          let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let decision = answer["decision"] as? String, decision == "allow" || decision == "deny"
    else { carryOn() }
    // Claude Code and Codex read the same answer.
    var verdict: [String: Any] = ["behavior": decision]
    if decision == "deny" { verdict["message"] = "Denied from Col." }
    let output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": verdict]]
    FileHandle.standardOutput.write(json(output))
    exit(0)
}

func linkPath() -> String { NSHomeDirectory() + "/.local/bin/colctl" }

/// The command's name before Islet became Col: hooks installed then call it, and its link now leads here too.
func legacyLinkPath() -> String { NSHomeDirectory() + "/.local/bin/islet" }

/// Whether a hook's command is this one, under its name or Islet's.
func callsCol(_ command: Any?) -> Bool {
    guard let command = command as? String else { return false }
    return ["colctl", "islet"].contains { name in
        command.contains("\(name)\" hook") || command.hasSuffix("\(name) hook") || command.contains("\(name) hook --agent")
    }
}

/// Whether a settings file, read as text, calls this command, under its name or Islet's.
func mentionsCol(_ text: String) -> Bool {
    ["colctl", "islet"].contains { text.contains("\($0)\\\" hook") || text.contains("\($0)\" hook") || text.contains("\($0) hook") }
}

/// The file Islet wrote Copilot's hooks to, which still calls Col through ~/.local/bin/islet.
func legacyCopilotHooksPath() -> String { ("~/.copilot/hooks/islet.json" as NSString).expandingTildeInPath }

/// Sets aside the file Islet wrote Copilot's hooks to, as `islet.json.col-backup`. VS Code reads every file of the
/// folder: once Col writes its own, each event would come twice, and once Copilot is disconnected, Islet's hooks would
/// still call Col. Returns where the file went, or nil when there was none calling Col.
func setAsideLegacyCopilotHooks() throws -> String? {
    let legacy = legacyCopilotHooksPath()
    guard let text = try? String(contentsOfFile: legacy, encoding: .utf8), mentionsCol(text) else { return nil }
    let aside = legacy + ".col-backup"
    do {
        if (try? FileManager.default.attributesOfItem(atPath: aside)) != nil { try FileManager.default.removeItem(atPath: aside) }
        try FileManager.default.moveItem(atPath: legacy, toPath: aside)
    } catch {
        throw ClientError.failed("could not set aside \(legacy): \(error.localizedDescription)")
    }
    return aside
}

/// True for an entry Col wrote: a matcher group holding Col's command, or Cursor's plain command entry.
func isColHook(_ entry: Any) -> Bool {
    guard let entry = entry as? [String: Any] else { return false }
    if callsCol(entry["command"]) { return true }
    guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
    return hooks.contains { callsCol($0["command"]) }
}

func entry(for agent: Agent, _ event: (name: String, matcher: Bool, timeout: Int)) -> [String: Any] {
    switch agent.format {
    case .claude:
        var group: [String: Any] = ["hooks": [["type": "command", "command": agent.command, "timeout": event.timeout]]]
        if event.matcher { group["matcher"] = "*" }
        return group
    case .gemini:
        // Gemini CLI counts timeouts in milliseconds and expects a matcher on every group.
        return ["matcher": "*", "hooks": [["name": "col", "type": "command", "command": agent.command, "timeout": event.timeout * 1000]]]
    case .cursor:
        return ["command": agent.command]
    case .vscode:
        return ["type": "command", "command": agent.command, "timeout": event.timeout]
    }
}

/// Keeps a copy of an agent's settings beside them, readable by its owner only, whatever the umask: the settings can
/// hold keys and tokens, and the folder they sit in is often open to the Mac's other accounts. The copy is written
/// whole under another name, then put in place, so it is never readable by others for a moment either.
func backUp(_ data: Data, of url: URL) {
    // Islet left its own copy beside the settings, readable by others: it is closed to them too.
    let legacy = url.appendingPathExtension("islet-backup").path
    var status = stat()
    if lstat(legacy, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_mode & 0o077 != 0 {
        fchmodat(AT_FDCWD, legacy, status.st_mode & 0o700, AT_SYMLINK_NOFOLLOW)
    }
    let backup = url.appendingPathExtension("col-backup").path
    let partial = backup + ".\(getpid())"
    unlink(partial)
    let file = open(partial, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard file >= 0 else { return }
    let written = data.withUnsafeBytes { buffer -> Bool in
        var offset = 0
        while offset < buffer.count {
            let count = write(file, buffer.baseAddress! + offset, buffer.count - offset)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
    close(file)
    if !written || rename(partial, backup) != 0 { unlink(partial) }
}

/// Adds or removes Col's hooks in an agent's settings, keeping everything else and a backup of the file.
func editSettings(_ agent: Agent, path: String?, install: Bool) throws -> String {
    let url = URL(fileURLWithPath: ((path ?? agent.settings) as NSString).expandingTildeInPath)
    var settings: [String: Any] = [:]
    if let data = try? Data(contentsOf: url), !data.isEmpty {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.failed("\(url.path) is not valid JSON; left untouched")
        }
        settings = parsed
        backUp(data, of: url)
    } else if !install {
        // Copilot connected under Islet has no file of Col's yet: its hooks are all in Islet's.
        if agent.id == "copilot", let aside = try setAsideLegacyCopilotHooks() {
            return "\(agent.name): Col's hooks removed. Islet's \(legacyCopilotHooksPath()) is kept as \(aside)."
        }
        return "\(agent.name): nothing to remove."
    }
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    for event in agent.events {
        var groups = (hooks[event.name] as? [Any] ?? []).filter { !isColHook($0) }
        if install { groups.append(entry(for: agent, event)) }
        hooks[event.name] = groups.isEmpty ? nil : groups
    }
    settings["hooks"] = hooks.isEmpty ? nil : hooks
    if agent.format == .cursor, install { settings["version"] = settings["version"] ?? 1 }

    if install {
        // The hooks call the command through ~/.local/bin, so moving the app never breaks them.
        let tool = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        // A link that already leads here, through Homebrew's link for instance, is left as it is.
        func leadsElsewhere(_ link: String, _ destination: String) -> Bool {
            let parent = URL(fileURLWithPath: link).deletingLastPathComponent()
            return URL(fileURLWithPath: destination, relativeTo: parent).resolvingSymlinksInPath().path != tool.path
        }
        // Islet's link, which older hooks call, leads to this command too.
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: legacyLinkPath()),
           leadsElsewhere(legacyLinkPath(), destination) {
            try? FileManager.default.removeItem(atPath: legacyLinkPath())
            try? FileManager.default.createSymbolicLink(atPath: legacyLinkPath(), withDestinationPath: tool.path)
        }
        let link = linkPath()
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link) {
            if leadsElsewhere(link, destination) {
                try? FileManager.default.removeItem(atPath: link)
                try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: tool.path)
            }
        } else if !FileManager.default.fileExists(atPath: link) {
            try? FileManager.default.createDirectory(atPath: (link as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: tool.path)
        }
    }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    } catch {
        throw ClientError.failed("could not write \(url.path): \(error.localizedDescription)")
    }
    // Once Col's own file is written, so that Copilot keeps calling Col if that fails.
    let legacyAside = agent.id == "copilot" ? try setAsideLegacyCopilotHooks() : nil
    var message = install
        ? "\(agent.name): hooks installed in \(url.path). New sessions report to Col."
        : "\(agent.name): Col's hooks removed from \(url.path)."
    if let legacyAside { message += " Islet's \(legacyCopilotHooksPath()) is kept as \(legacyAside)." }
    if agent.id == "codex", install { message += " Codex asks you to review new hooks once: run /hooks in Codex and trust Col's." }
    return message
}

/// Whether an agent's settings call Col.
func isConnected(_ agent: Agent) -> Bool {
    let url = URL(fileURLWithPath: (agent.settings as NSString).expandingTildeInPath)
    var paths = [url.path]
    if agent.id == "copilot" { paths.append(legacyCopilotHooksPath()) }
    return paths.contains { path in
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return mentionsCol(text)
    }
}

// MARK: Commands

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else {
    print(usage)
    exit(0)
}

switch command {
case "push":
    guard let id = arguments.dropFirst().first, !id.hasPrefix("--") else { fail("push needs an id") }
    let values = options(arguments.dropFirst(2))
    var body: [String: Any] = ["id": id]
    for key in ["title", "subtitle", "symbol", "tint", "text", "priority"] { body[key] = values[key] }
    if let progress = values["progress"] {
        guard let fraction = percentOrFraction(progress) else { fail("--progress takes 0 to 1, or a percentage") }
        body["progress"] = fraction
    }
    if let ttl = values["ttl"] {
        guard let seconds = Double(ttl) else { fail("--ttl takes seconds") }
        body["ttl"] = seconds
    }
    _ = run("POST", "/v1/activities", body: json(body))

case "done":
    guard let id = arguments.dropFirst().first else { fail("done needs an id") }
    let text = options(arguments.dropFirst(2))["text"]
    let query = text.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }.map { "?text=\($0)" } ?? ""
    _ = run("POST", "/v1/activities/\(id)/done\(query)")

case "remove":
    guard let id = arguments.dropFirst().first else { fail("remove needs an id") }
    _ = run("DELETE", "/v1/activities/\(id)")

case "list":
    let data = run("GET", "/v1/activities")
    let list = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["activities"] as? [[String: Any]] ?? []
    if list.isEmpty { print("No activities.") }
    for item in list {
        let id = item["id"] as? String ?? ""
        let title = item["title"] as? String ?? ""
        let detail = (item["progress"] as? Double).map { "\(Int($0 * 100))%" } ?? (item["text"] as? String ?? "")
        print([id, title, detail].filter { !$0.isEmpty }.joined(separator: "  "))
    }

case "status":
    let data = run("GET", "/v1/status")
    let info = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    print("Col \(info["version"] ?? "") is running: \(info["activities"] ?? 0) activities, \(info["agents"] ?? 0) agent sessions.")

case "agent":
    let rest = Array(arguments.dropFirst())
    guard rest.count >= 2 else { fail("agent needs a name and a state") }
    let states = ["working": "Working", "waiting": "Waiting", "done": "Done", "idle": "Idle", "end": "End"]
    guard let state = states[rest[1].lowercased()] else { fail("state is working, waiting, done, idle or end") }
    // Anything after the options (Codex passes its event as a last argument) is ignored.
    var values: [String: String] = [:]
    var index = 2
    while index + 1 < rest.count, rest[index].hasPrefix("--") {
        values[String(rest[index].dropFirst(2))] = rest[index + 1]
        index += 2
    }
    var event: [String: Any] = ["hook_event_name": state, "agent_name": rest[0], "session_id": values["session"] ?? rest[0].lowercased()]
    if let message = values["message"] { event["message"] = message }
    // Agents call this from their own hooks: never fail loudly when Col is closed.
    _ = try? request("POST", "/v1/agents/events", body: json(event), timeout: 3)

case "hook":
    let id = options(arguments.dropFirst())["agent"] ?? "claude"
    // An unknown agent still must not break the agent calling it.
    guard let agent = Agent.named(id) else { exit(0) }
    hook(agent)

case "hooks":
    let action = arguments.dropFirst().first ?? ""
    let values = options(arguments.dropFirst(2))
    let id = values["agent"] ?? "claude"
    guard id == "all" || Agent.named(id) != nil else { fail("unknown agent \(id): claude, codex, gemini, cursor, copilot or all") }
    let agents = id == "all" ? Agent.all : Agent.all.filter { $0.id == id }
    switch action {
    case "install", "uninstall":
        var failed = false
        for agent in agents {
            // With --agent all, only agents present on this Mac are connected.
            if id == "all", action == "install", !isInstalled(agent) {
                continue
            }
            do {
                print(try editSettings(agent, path: agents.count == 1 ? values["settings"] : nil, install: action == "install"))
            } catch ClientError.failed(let reason) {
                FileHandle.standardError.write(Data("colctl: \(reason)\n".utf8))
                failed = true
            }
        }
        exit(failed ? 1 : 0)
    case "status":
        for agent in Agent.all {
            print("\(agent.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(isConnected(agent) ? "connected" : "not connected")")
        }
    default:
        fail("hooks takes install, uninstall or status")
    }

case "help", "--help", "-h":
    print(usage)

default:
    fail("unknown command \(command). Run `colctl help`.")
}

func isInstalled(_ agent: Agent) -> Bool {
    let directory = ((agent.settings as NSString).deletingLastPathComponent as NSString).expandingTildeInPath
    if FileManager.default.fileExists(atPath: directory) { return true }
    guard agent.id == "copilot" else { return false }
    return [
        "/Applications/Visual Studio Code.app", NSHomeDirectory() + "/Applications/Visual Studio Code.app",
        "/Applications/Visual Studio Code - Insiders.app", NSHomeDirectory() + "/Applications/Visual Studio Code - Insiders.app",
        NSHomeDirectory() + "/.vscode/extensions",
    ]
        .contains { FileManager.default.fileExists(atPath: $0) }
}

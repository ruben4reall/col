import Foundation
import Testing
@testable import IsletCore

struct ActivityRequestTests {
    let now = Date(timeIntervalSince1970: 100)

    @Test func buildsARingForProgress() throws {
        let request = try ActivityRequest(id: " build ", symbol: "hammer.fill", tint: "orange", progress: 1.4, ttl: 30).validated()
        let activity = request.activity(now: now)
        #expect(activity.id == "api.build")
        #expect(activity.compact.leading == .symbol("hammer.fill", tint: .orange))
        #expect(activity.compact.trailing == .ring(progress: 1, tint: .orange))
        #expect(activity.expires == now.addingTimeInterval(30))
        #expect(activity.priority == .standard)
    }

    @Test func fallsBackToText() throws {
        let activity = try ActivityRequest(id: "deploy", text: "Live", priority: "alert").validated().activity(now: now)
        #expect(activity.compact.trailing == .text("Live", tint: .white))
        #expect(activity.priority == .alert)
    }

    @Test func rejectsBadIDs() {
        #expect(throws: ActivityRequest.Invalid.missingID) { try ActivityRequest(id: "  ").validated() }
        #expect(throws: ActivityRequest.Invalid.idTooLong) { try ActivityRequest(id: String(repeating: "x", count: 65)).validated() }
    }

    @Test func decodesJSON() throws {
        let json = #"{"id":"a","title":"T","progress":0.5}"#
        let request = try JSONDecoder().decode(ActivityRequest.self, from: Data(json.utf8))
        #expect(request.title == "T" && request.progress == 0.5)
    }

    @Test func parsesColours() {
        #expect(ColorName.parse("#FF8800") == RGBA(red: 1, green: 136.0 / 255, blue: 0))
        #expect(ColorName.parse("f80") == RGBA(red: 1, green: 136.0 / 255, blue: 0))
        #expect(ColorName.parse("Green") == .green)
        #expect(ColorName.parse("nope") == nil)
    }
}

struct AgentBoardTests {
    let t0 = Date(timeIntervalSince1970: 0)

    func event(_ name: String, tool: String? = nil, input: [String: JSONValue]? = nil, notification: String? = nil) -> HookEvent {
        HookEvent(sessionID: "s1", event: name, cwd: "/Users/me/islet", toolName: tool, toolInput: input, notificationType: notification)
    }

    @Test func followsASession() {
        var board = AgentBoard()
        board.apply(event("SessionStart"), at: t0)
        #expect(board.sessions["s1"]?.state == .idle)
        #expect(board.sessions["s1"]?.project == "islet")
        board.apply(event("UserPromptSubmit"), at: t0)
        board.apply(event("PreToolUse", tool: "Bash", input: ["command": .string("swift test\nmore")]), at: t0)
        #expect(board.sessions["s1"]?.state == .working("Bash · swift test"))
        board.apply(event("PermissionRequest", tool: "Edit", input: ["file_path": .string("/a/b/TASKS.md")]), at: t0)
        #expect(board.sessions["s1"]?.state == .waiting("Edit · TASKS.md"))
        board.apply(event("Notification", notification: "permission_prompt"), at: t0)
        #expect(board.sessions["s1"]?.state == .waiting("Edit · TASKS.md"))
        board.apply(event("Stop"), at: t0)
        #expect(board.sessions["s1"]?.state == .done)
        board.apply(event("SessionEnd"), at: t0)
        #expect(board.sessions.isEmpty)
    }

    @Test func descriptionBeatsTheRawCommand() {
        let summary = event("PreToolUse", tool: "Bash", input: ["command": .string("rm -rf x"), "description": .string("Clean build")]).toolSummary
        #expect(summary == "Bash · Clean build")
    }

    @Test func doneSettlesToIdle() {
        var board = AgentBoard()
        board.apply(event("Stop"), at: t0)
        board.settle(now: t0.addingTimeInterval(3))
        #expect(board.sessions["s1"]?.state == .done)
        board.settle(now: t0.addingTimeInterval(7))
        #expect(board.sessions["s1"]?.state == .idle)
    }

    @Test func theNotchShowsTheMostUrgentSession() {
        var board = AgentBoard()
        board.apply(HookEvent(sessionID: "a", event: "UserPromptSubmit"), at: t0)
        board.apply(HookEvent(sessionID: "b", event: "PermissionRequest", toolName: "Bash"), at: t0)
        let activity = board.activity(now: t0, tint: .white)
        #expect(activity?.priority == .alert)
        #expect(activity?.compact.trailing == .symbol("hand.raised.fill", tint: .orange))
        #expect(board.ordered.first?.id == "b")
    }

    @Test func eachAgentUsesDistinctIconInNotch() {
        let symbols: [(CodingAgent, String)] = [
            (.claude, "sparkle"), (.codex, "curlybraces.square"), (.gemini, "sparkles"),
            (.cursor, "cursorarrow"), (.copilot, "chevron.left.forwardslash.chevron.right"),
        ]
        for (agent, symbol) in symbols {
            var board = AgentBoard()
            board.apply(HookEvent(sessionID: agent.rawValue, event: "UserPromptSubmit", agent: agent), at: t0)
            #expect(CodingAgent.symbol(for: agent.name) == symbol)
            // The app's own icon, its symbol standing in when the app is not installed.
            #expect(board.activity(now: t0, tint: .white)?.compact.leading == .appIcon(agent.icon))
            #expect(agent.icon.symbol == symbol)
        }
        #expect(Set(CodingAgent.allCases.map(\.icon)).count == CodingAgent.allCases.count)
        #expect(CodingAgent.symbol(for: nil) == "sparkle")
    }

    @Test func idleAgentsStayOutOfTheNotch() {
        var board = AgentBoard()
        board.apply(event("SessionStart"), at: t0)
        #expect(board.activity(now: t0, tint: .white) == nil)
    }

    @Test func decodesARealHookPayload() throws {
        let json = #"{"session_id":"abc","hook_event_name":"PreToolUse","cwd":"/tmp/p","tool_name":"Read","tool_input":{"file_path":"/tmp/p/README.md","limit":20},"permission_mode":"default"}"#
        let event = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
        #expect(event.toolSummary == "Read · README.md")
        #expect(event.project == "p")
    }

    @Test func followsAnyAgentThroughGenericStates() {
        var board = AgentBoard()
        board.apply(HookEvent(sessionID: "codex", event: "Working", message: "Refactor", agentName: "Codex"), at: t0)
        #expect(board.sessions["codex"]?.project == "Codex")
        #expect(board.sessions["codex"]?.state == .working("Refactor"))
        board.apply(HookEvent(sessionID: "codex", event: "Waiting", message: "Approve the plan", agentName: "Codex"), at: t0)
        #expect(board.activity(now: t0, tint: .white)?.priority == .alert)
        board.apply(HookEvent(sessionID: "codex", event: "End", agentName: "Codex"), at: t0)
        #expect(board.sessions.isEmpty)
    }
}

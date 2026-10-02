import Foundation
import Testing
@testable import ColCore

@Suite struct CodingAgentTests {
    func raw(_ json: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    }

    @Test func codexSpeaksLikeClaudeCode() throws {
        let event = try #require(CodingAgent.codex.event(from: raw("""
        {"session_id":"c1","hook_event_name":"PermissionRequest","cwd":"/Users/me/col","model":"gpt-5",
         "tool_name":"Bash","tool_input":{"command":"rm -rf build"}}
        """)))
        #expect(event.event == "PermissionRequest")
        #expect(event.agent == .codex)
        #expect(event.project == "col")
        #expect(event.toolSummary == "Bash · rm -rf build")
        #expect(CodingAgent.codex.answersPermissions)
    }

    @Test func geminiEventsBecomeTheSameStates() throws {
        let tool = try #require(CodingAgent.gemini.event(from: raw("""
        {"session_id":"g1","hook_event_name":"BeforeTool","cwd":"/tmp/site","timestamp":"2026-09-27T12:00:00Z",
         "tool_name":"run_shell_command","tool_input":{"command":"npm test\\nnpm run build"}}
        """)))
        #expect(tool.event == "PreToolUse")
        #expect(tool.toolSummary == "Shell · npm test")
        let ask = try #require(CodingAgent.gemini.event(from: raw("""
        {"session_id":"g1","hook_event_name":"Notification","notification_type":"ToolPermission","message":"Allow write_file?"}
        """)))
        #expect(ask.notificationType == "permission_prompt")
        let done = try #require(CodingAgent.gemini.event(from: raw(#"{"session_id":"g1","hook_event_name":"AfterAgent"}"#)))
        #expect(done.event == "Stop")
        #expect(CodingAgent.gemini.event(from: try raw(#"{"session_id":"g1","hook_event_name":"BeforeModel"}"#)) == nil)
        #expect(!CodingAgent.gemini.answersPermissions)

        var board = AgentBoard()
        board.apply(tool, at: Date())
        board.apply(ask, at: Date())
        #expect(board.ordered.first?.state == .waiting("Allow write_file?"))
        #expect(board.ordered.first?.agent == "Gemini CLI")
    }

    @Test func cursorConversationsBecomeSessions() throws {
        let edit = try #require(CodingAgent.cursor.event(from: raw("""
        {"conversation_id":"k1","generation_id":"x","hook_event_name":"afterFileEdit","workspace_roots":["/Users/me/shop"],
         "file_path":"/Users/me/shop/src/cart.ts","edits":[]}
        """)))
        #expect(edit.sessionID == "k1")
        #expect(edit.event == "PostToolUse")
        #expect(edit.project == "shop")
        #expect(edit.toolSummary == "Edit · cart.ts")
        let shell = try #require(CodingAgent.cursor.event(from: raw("""
        {"conversation_id":"k1","hook_event_name":"afterShellExecution","command":"pnpm lint","output":"ok"}
        """)))
        #expect(shell.toolSummary == "Shell · pnpm lint")
        #expect(try CodingAgent.cursor.event(from: raw(#"{"conversation_id":"k1","hook_event_name":"stop","status":"completed"}"#))?.event == "Stop")
        #expect(CodingAgent.cursor.event(from: try raw(#"{"conversation_id":"k1","hook_event_name":"beforeReadFile"}"#)) == nil)
    }

    @Test func scriptsReportedWithColAgentKeepTheirName() throws {
        let event = try #require(CodingAgent.claude.event(from: raw("""
        {"session_id":"aider","hook_event_name":"Working","agent_name":"Aider"}
        """)))
        #expect(event.agent == nil)
        #expect(event.project == "Aider")
    }

    @Test func vscodeCopilotEventsUseLocalHookPayloads() throws {
        let event = try #require(CodingAgent.copilot.event(from: raw("""
        {"session_id":"v1","hook_event_name":"UserPromptSubmit","cwd":"/Users/me/shop",
         "prompt":"Show me the current project status"}
        """)))
        #expect(event.agent == .copilot)
        #expect(event.event == "UserPromptSubmit")
        #expect(event.project == "shop")
        // The prompt is never read: the island shows that Copilot works, not what it was asked.
        #expect(event.message == nil)
        #expect(!CodingAgent.copilot.answersPermissions)

        var board = AgentBoard()
        board.apply(event, at: Date())
        #expect(board.ordered.first?.state == .working(nil))

        let permission = try #require(CodingAgent.copilot.event(from: raw("""
        {"session_id":"v1","hook_event_name":"PreToolUse","cwd":"/Users/me/shop",
         "tool_name":"run_in_terminal","tool_input":{"command":"swift test"}}
        """)))
        #expect(permission.event == "PreToolUse")
        #expect(permission.toolSummary == "run_in_terminal · swift test")
        board.apply(permission, at: Date())
        #expect(board.ordered.first?.state == .working("run_in_terminal · swift test"))

        // Stop ends an answer: Done, as for the other agents, then the session leaves once it has settled, since VS
        // Code never says a chat is over.
        let stop = try #require(CodingAgent.copilot.event(from: raw("""
        {"session_id":"v1","hook_event_name":"Stop","cwd":"/Users/me/shop","stop_hook_active":false}
        """)))
        #expect(stop.event == "Stop")
        let end = Date()
        board.apply(stop, at: end)
        #expect(board.ordered.first?.state == .done)
        board.settle(now: end.addingTimeInterval(7))
        #expect(board.sessions.isEmpty)
    }

    @Test func agentsThatEndTheirSessionsStayIdleAfterDone() {
        var board = AgentBoard()
        let start = Date()
        board.apply(HookEvent(sessionID: "c1", event: "UserPromptSubmit", cwd: "/Users/me/shop", agent: .claude), at: start)
        board.apply(HookEvent(sessionID: "c1", event: "Stop", cwd: "/Users/me/shop", agent: .claude), at: start)
        board.settle(now: start.addingTimeInterval(7))
        #expect(board.ordered.first?.state == .idle)
        #expect(CodingAgent.named("Claude Code")?.endsSessions == true)
        #expect(CodingAgent.named(CodingAgent.copilot.name)?.endsSessions == false)
    }
}

struct AgentIconTests {
    let now = Date(timeIntervalSince1970: 10_000)

    @Test func eachAgentShowsItsOwnLogo() {
        #expect(CodingAgent.claude.icon.bundleIdentifiers == ["com.anthropic.claudefordesktop"])
        #expect(CodingAgent.claude.icon.name == "Claude")
        #expect(CodingAgent.claude.icon.mark == "claude")
        #expect(CodingAgent.gemini.icon.mark == "gemini")
        // Codex lives in ChatGPT now and Copilot runs in VS Code: neither app is their logo.
        #expect(CodingAgent.codex.icon.bundleIdentifiers.isEmpty && CodingAgent.codex.icon.mark == "codex")
        #expect(CodingAgent.copilot.icon.bundleIdentifiers.isEmpty && CodingAgent.copilot.icon.mark == "githubcopilot")
        for agent in CodingAgent.allCases { #expect(agent.icon.mark != nil) }
    }

    @Test func agentsReportingByNameFindTheirApp() {
        #expect(CodingAgent.icon(for: "Claude Code") == CodingAgent.claude.icon)
        #expect(CodingAgent.icon(for: "opencode").bundleIdentifiers == ["ai.opencode.desktop"])
        #expect(CodingAgent.icon(for: "OpenCode").mark == "opencode")
        #expect(CodingAgent.icon(for: "my-script") == .col)
        #expect(CodingAgent.icon(for: nil) == .col)
        #expect(ModelServerKind.ollama.icon.bundleIdentifiers == ["com.electron.ollama"])
        #expect(ModelServerKind.ollama.icon.mark == "ollama")
        #expect(ModelServerKind.llamaCpp.icon.bundleIdentifiers.isEmpty && ModelServerKind.llamaCpp.icon.mark == nil)
    }

    @Test func theAgentsIconHopsOnceForEachNewWait() throws {
        let icon = CodingAgent.gemini.icon
        var board = AgentBoard()
        board.apply(HookEvent(sessionID: "s", event: "UserPromptSubmit", cwd: "/x/col", agent: .gemini), at: now)
        let working = try #require(board.activity(now: now, tint: .white))
        #expect(working.compact.leading == .appIcon(icon, attention: nil))

        let asked = now.addingTimeInterval(5)
        board.apply(HookEvent(sessionID: "s", event: "PermissionRequest", cwd: "/x/col", toolName: "Bash", agent: .gemini), at: asked)
        let waiting = try #require(board.activity(now: asked, tint: .white))
        #expect(waiting.compact.leading == .appIcon(icon, attention: asked))

        // The same wait told again, and the minutes it lasts, keep its moment: the icon does not hop for it twice.
        let later = asked.addingTimeInterval(90)
        board.apply(HookEvent(sessionID: "s", event: "Notification", cwd: "/x/col", notificationType: "permission_prompt",
                              message: "Gemini needs your permission", agent: .gemini), at: later)
        #expect(board.activity(now: later.addingTimeInterval(3600), tint: .white)?.compact.leading == .appIcon(icon, attention: asked))

        // Another session that starts to wait is a new request.
        let second = later.addingTimeInterval(30)
        board.apply(HookEvent(sessionID: "t", event: "PermissionRequest", cwd: "/x/site", toolName: "Bash", agent: .gemini), at: second)
        #expect(board.activity(now: second, tint: .white)?.compact.leading == .appIcon(icon, attention: second))

        // A session idle at its prompt waits from the moment it is told so.
        board.forget("s")
        board.forget("t")
        board.apply(HookEvent(sessionID: "u", event: "Stop", cwd: "/x/col", agent: .gemini), at: second)
        board.settle(now: second.addingTimeInterval(6))
        let idle = second.addingTimeInterval(60)
        board.apply(HookEvent(sessionID: "u", event: "Notification", cwd: "/x/col", notificationType: "idle_prompt", agent: .gemini), at: idle)
        #expect(board.activity(now: idle, tint: .white)?.compact.leading == .appIcon(icon, attention: idle))
    }
}

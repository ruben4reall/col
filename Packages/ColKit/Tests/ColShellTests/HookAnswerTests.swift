import ColCore
import Foundation
import Testing
@testable import ColShell

/// `colctl`, built from CLI/main.swift for these tests, or nil when it does not build.
private let hookTool: URL? = {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../../CLI/main.swift").standardizedFileURL
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("col-colctl-hook-tests")
    try? FileManager.default.removeItem(at: folder)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let tool = folder.appendingPathComponent("colctl")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swiftc", "-swift-version", "6", "-module-name", "ColCommand", source.path, "-o", tool.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    return process.terminationStatus == 0 ? tool.resolvingSymlinksInPath() : nil
}()

/// A Claude Code PermissionRequest goes through `colctl hook` to Col's local API, waits for the island, and comes back
/// as the output Claude Code reads: what Claude Code 2.1.289 was seen to accept, in a run of its own, for questions
/// (`answers`) and plans (the input handed back).
@MainActor
@Suite(.serialized) struct HookAnswerTests {
    private func withAPI(_ body: (AgentCenter, String) async throws -> Void) async throws {
        let socket = FileManager.default.temporaryDirectory.appendingPathComponent("ch-\(UUID().uuidString.prefix(8)).sock").path
        setenv("COL_SOCKET", socket, 1)
        defer { unsetenv("COL_SOCKET") }
        let agents = AgentCenter()
        let api = ControlAPI(custom: CustomActivities(), agents: agents, widgets: WidgetCenter(file: nil, definitions: []),
                             post: { _ in }, remove: { _ in })
        api.start()
        defer { api.stop() }
        try await body(agents, socket)
    }

    /// Runs the hook with this event on its stdin; `answer` is called once the request waits in the island.
    private func hook(_ event: String, socket: String, agents: AgentCenter, answer: (AgentCenter.PendingRequest) -> Void) async throws -> [String: Any] {
        let tool = try #require(hookTool)
        let process = Process()
        process.executableURL = tool
        process.arguments = ["hook"]
        process.environment = ["COL_SOCKET": socket, "HOME": FileManager.default.temporaryDirectory.path, "PATH": "/usr/bin:/bin"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(event.utf8))
        try input.fileHandleForWriting.close()
        for _ in 0..<500 where agents.pending.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        answer(try #require(agents.pending.values.first))
        let data = await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        process.waitUntilExit()
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func aQuestionAnsweredInTheIslandReachesClaudeCode() async throws {
        try await withAPI { agents, socket in
            let event = """
            {"session_id":"q","hook_event_name":"PermissionRequest","cwd":"/tmp/app","permission_mode":"default",
             "tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which colour do you prefer?","header":"Colour",
             "options":[{"label":"Red","description":"Warm"},{"label":"Blue","description":"Cool"}],"multiSelect":false}]}}
            """
            let output = try await hook(event, socket: socket, agents: agents) { request in
                #expect(agents.answer(request.id, choices: ["Which colour do you prefer?": ["Blue"]]))
            }
            let specific = try #require(output["hookSpecificOutput"] as? [String: Any])
            #expect(specific["hookEventName"] as? String == "PermissionRequest")
            let decision = try #require(specific["decision"] as? [String: Any])
            #expect(decision["behavior"] as? String == "allow")
            let input = try #require(decision["updatedInput"] as? [String: Any])
            #expect((input["answers"] as? [String: String]) == ["Which colour do you prefer?": "Blue"])
            #expect((input["questions"] as? [[String: Any]])?.first?["header"] as? String == "Colour")
            // Where the session runs came with the event.
            #expect(agents.origins["q"]?.processes.isEmpty == false)
        }
    }

    @Test func anApprovedPlanReachesClaudeCode() async throws {
        try await withAPI { agents, socket in
            let event = ##"""
            {"session_id":"p","hook_event_name":"PermissionRequest","cwd":"/tmp/app","permission_mode":"plan",
             "tool_name":"ExitPlanMode","tool_input":{"plan":"# Refactor\n\n1. Split","planFilePath":"/tmp/plans/a.md"}}
            """##
            let output = try await hook(event, socket: socket, agents: agents) { request in
                agents.decide(request.id, .allow)
            }
            let decision = try #require((output["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
            #expect(decision["behavior"] as? String == "allow")
            let input = try #require(decision["updatedInput"] as? [String: Any])
            #expect(input["plan"] as? String == "# Refactor\n\n1. Split")
            #expect(input["planFilePath"] as? String == "/tmp/plans/a.md")
        }
    }

    @Test func keepPlanningTellsClaudeCodeWhy() async throws {
        try await withAPI { agents, socket in
            let event = ##"{"session_id":"p","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode","tool_input":{"plan":"# Plan"}}"##
            let output = try await hook(event, socket: socket, agents: agents) { request in
                agents.decide(request.id, .deny)
            }
            let decision = try #require((output["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
            #expect(decision["behavior"] as? String == "deny")
            #expect((decision["message"] as? String)?.contains("keep planning") == true)
            #expect(decision["updatedInput"] == nil)
        }
    }
}

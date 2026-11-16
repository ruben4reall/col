import AppKit
import ColCore
import Foundation
import Testing
@testable import ColShell

/// Plans and questions from Claude Code, answered from the island: what the hook hears back is what Claude Code 2.1
/// reads from a PermissionRequest hook (`allow` with `updatedInput`).
@MainActor
@Suite struct AgentAnswerTests {
    private func raw(_ json: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    }

    private func event(_ tool: String, _ input: String) throws -> HookEvent {
        HookEvent(sessionID: "s", event: "PermissionRequest", cwd: "/tmp/app", toolName: tool, toolInput: try raw(input), agent: .claude)
    }

    @Test func anApprovedPlanIsTheOneInItsFile() throws {
        let center = AgentCenter()
        let answers = AnswerRecorder()
        let plan = try event("ExitPlanMode", ##"{"plan":"# Refactor\n\n1. Split","planFilePath":"/Users/me/.claude/plans/a.md"}"##)
        center.receive(plan, origin: nil) { answers.record($0) }
        let request = try #require(center.pending.values.first)
        #expect(request.kind == .plan("# Refactor\n\n1. Split", file: "/Users/me/.claude/plans/a.md"))
        #expect(AgentCenter.canAllow(request))
        center.decide(request.id, .allow)
        let answer = try #require(answers.last)
        #expect(answer.decision == .allow)
        // Sent back, the plan would read as the user's own edit, over any made in the terminal meanwhile.
        #expect(answer.updatedInput == [:])
        let json = answer.json
        #expect(json["decision"] as? String == "allow")
        #expect((json["updatedInput"] as? [String: Any])?.isEmpty == true)
    }

    @Test func keepPlanningDenies() throws {
        let center = AgentCenter()
        let answers = AnswerRecorder()
        center.receive(try event("ExitPlanMode", ##"{"plan":"# Plan"}"##), origin: nil) { answers.record($0) }
        center.decide(try #require(center.pending.keys.first), .deny)
        #expect(answers.last?.decision == .deny)
        #expect(answers.last?.message?.contains("keep planning") == true)
    }

    @Test func questionsAreAnsweredWithTheirOptions() throws {
        let center = AgentCenter()
        let answers = AnswerRecorder()
        let question = try event("AskUserQuestion", """
        {"questions":[{"question":"Which colour do you prefer?","header":"Colour","multiSelect":false,
          "options":[{"label":"Red","description":"Warm"},{"label":"Blue","description":"Cool"}]}]}
        """)
        center.receive(question, origin: nil) { answers.record($0) }
        let request = try #require(center.pending.values.first)
        guard case .questions(let questions) = request.kind else { Issue.record("not questions"); return }
        #expect(questions.first?.options.map(\.label) == ["Red", "Blue"])
        // Allow alone would let Claude Code run the tool without an answer: the island never sends it.
        #expect(!AgentCenter.canAllow(request))
        center.decide(request.id, .allow)
        #expect(answers.last == AgentCenter.Answer(decision: .ask))

        center.receive(question, origin: nil) { answers.record($0) }
        let again = try #require(center.pending.values.first)
        #expect(!center.answer(again.id, choices: ["Which colour do you prefer?": ["Green"]]))
        #expect(center.pending.count == 1)
        #expect(center.answer(again.id, choices: ["Which colour do you prefer?": ["Blue"]]))
        let answer = try #require(answers.last)
        #expect(answer.decision == .allow)
        #expect(answer.updatedInput?["answers"] == .object(["Which colour do you prefer?": .string("Blue")]))
        #expect(answer.updatedInput?["questions"] == question.toolInput?["questions"])
        #expect(center.pending.isEmpty)
    }

    @Test func originsFollowTheirSessions() throws {
        let center = AgentCenter()
        let origin = AgentOrigin(query: ["tty": "ttys004", "pids": "812,640,1,abc"], folder: "/tmp/app")
        #expect(origin?.tty == "ttys004")
        #expect(origin?.processes == [812, 640])
        center.receive(HookEvent(sessionID: "s", event: "SessionStart", cwd: "/tmp/app", agent: .claude), origin: origin) { _ in }
        #expect(center.origins["s"] == origin)
        center.receive(HookEvent(sessionID: "s", event: "SessionEnd", agent: .claude), origin: nil) { _ in }
        #expect(center.origins["s"] == nil)
    }

    @Test func onlyATerminalsNameReachesAScript() {
        #expect(AgentOrigin(query: ["tty": "ttys004\"; do shell script \"x"], folder: nil) == nil)
        #expect(AgentOrigin(query: ["tty": "../ttys1"], folder: nil) == nil)
        #expect(AgentOrigin.isTerminal("ttys012"))
        #expect(AgentOrigin.isTerminal("tty3"))
        #expect(!AgentOrigin.isTerminal("ttys"))
        #expect(!AgentOrigin.isTerminal("ttys12345"))
        #expect(!AgentOrigin.isTerminal("ttys1٣"))
        #expect(AgentReveal.selectTab(tty: "ttys012", app: .terminal)?.contains("\"/dev/ttys012\"") == true)
        #expect(AgentReveal.selectTab(tty: "ttys012\" & quit", app: .iTerm) == nil)
        #expect(AgentReveal.selectTab(tty: "ttys012", app: .other) == nil)
        #expect(AgentReveal.kind(of: "com.apple.Terminal") == .terminal)
        #expect(AgentReveal.kind(of: "com.googlecode.iterm2") == .iTerm)
        #expect(AgentReveal.kind(of: "com.todesktop.230313mzl4w4u92") == .folderEditor)
        #expect(AgentReveal.kind(of: "com.mitchellh.ghostty") == .other)
    }

    @Test func aPlanKeepsItsButtonsInSightInEverySize() {
        func page(_ size: IslandSize) -> CGFloat { size.open.content - Theme.inset.top - Theme.inset.bottom }
        for size in IslandSize.allCases {
            #expect(PermissionCardLayout.planBottom <= page(size))
        }
    }
}

private final class AnswerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [AgentCenter.Answer] = []

    func record(_ answer: AgentCenter.Answer) {
        lock.withLock { answers.append(answer) }
    }

    var last: AgentCenter.Answer? { lock.withLock { answers.last } }
}

import Foundation
import Testing
@testable import ColCore

@Suite struct AgentQuestionTests {
    func raw(_ json: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    }

    /// The input Claude Code 2.1 gives its PermissionRequest hook for AskUserQuestion.
    var input: [String: JSONValue] {
        get throws {
            try raw("""
            {"questions":[{"question":"Which colour do you prefer?","header":"Colour","multiSelect":false,
              "options":[{"label":"Red","description":"Warm"},{"label":"Blue","description":"Cool"}]},
             {"question":"Which sizes?","header":"Sizes","multiSelect":true,
              "options":[{"label":"S"},{"label":"M"},{"label":"L"}]}]}
            """)
        }
    }

    @Test func readsTheQuestions() throws {
        let questions = try #require(AgentQuestion.questions(from: input))
        #expect(questions.count == 2)
        #expect(questions[0].header == "Colour")
        #expect(questions[0].options == [.init(label: "Red", detail: "Warm"), .init(label: "Blue", detail: "Cool")])
        #expect(!questions[0].multiSelect)
        #expect(questions[1].multiSelect)
        #expect(AgentQuestion.questions(from: try raw(#"{"questions":[]}"#)) == nil)
        #expect(AgentQuestion.questions(from: try raw(#"{"questions":[{"question":"No options","options":[]}]}"#)) == nil)
        #expect(AgentQuestion.questions(from: nil) == nil)
    }

    @Test func answersAsClaudeCodeReadsThem() throws {
        let answered = try #require(AgentQuestion.answering(input, with: [
            "Which colour do you prefer?": ["Blue"], "Which sizes?": ["L", "S"],
        ]))
        // The questions go back as they were asked, with the answers beside them.
        #expect(answered["questions"] == (try input)["questions"])
        #expect(answered["answers"] == .object(["Which colour do you prefer?": .string("Blue"), "Which sizes?": .string("S, L")]))
    }

    @Test func refusesAnswersItWasNotOffered() throws {
        // A question left out, a label that is not an option, two answers to a single choice.
        #expect(AgentQuestion.answering(try input, with: ["Which colour do you prefer?": ["Blue"]]) == nil)
        #expect(AgentQuestion.answering(try input, with: ["Which colour do you prefer?": ["Green"], "Which sizes?": ["S"]]) == nil)
        #expect(AgentQuestion.answering(try input, with: ["Which colour do you prefer?": ["Red", "Blue"], "Which sizes?": ["S"]]) == nil)
        #expect(AgentQuestion.answering(try input, with: ["Which colour do you prefer?": ["Red", "Purple"], "Which sizes?": ["S"]]) == nil)
    }

    @Test func requestsSayWhatTheyAreFor() throws {
        let question = try #require(CodingAgent.claude.event(from: raw("""
        {"session_id":"s","hook_event_name":"PermissionRequest","cwd":"/tmp/app","tool_name":"AskUserQuestion",
         "tool_input":{"questions":[{"question":"Which colour?","header":"Colour","options":[{"label":"Red"}]}]}}
        """)))
        #expect(question.requestSummary == "Question · Which colour?")
        #expect(question.questions?.first?.question == "Which colour?")
        #expect(question.plan == nil)
        let plan = try #require(CodingAgent.claude.event(from: raw("""
        {"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode",
         "tool_input":{"plan":"# Refactor the parser\\n\\n1. Split the lexer","planFilePath":"/Users/me/.claude/plans/a.md"}}
        """)))
        #expect(plan.plan == "# Refactor the parser\n\n1. Split the lexer")
        #expect(plan.requestSummary == "Plan · Refactor the parser")
        #expect(plan.questions == nil)
    }

    @Test func readsAPlansBlocks() {
        let blocks = MarkdownDocument.blocks("""
        # Refactor the parser

        Split it in **two**,
        then test.

        1. Split the lexer
        2. Add `tests`
           - nested
        - [x] done
        > quoted
        ---
        ```swift
        let x = 1

        print(x)
        ```
        """)
        #expect(blocks == [
            .heading(level: 1, text: "Refactor the parser"),
            .paragraph("Split it in **two**, then test."),
            .item(marker: "1.", text: "Split the lexer", depth: 0),
            .item(marker: "2.", text: "Add `tests`", depth: 0),
            .item(marker: "•", text: "nested", depth: 1),
            .item(marker: "☑", text: "done", depth: 0),
            .quote("quoted"),
            .rule,
            .code("let x = 1\n\nprint(x)"),
        ])
        #expect(MarkdownDocument.title("Intro line\n\n## Later") == "Later")
        #expect(MarkdownDocument.title("Just **one** line") == "Just one line")
        // A fence never closed keeps its code.
        #expect(MarkdownDocument.blocks("```\nopen") == [.code("open")])
    }
}

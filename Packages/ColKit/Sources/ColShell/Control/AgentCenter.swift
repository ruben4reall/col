import AppKit
import ColCore
import Observation

/// Follows the coding agents that report through their hooks, and holds their permission requests until the user
/// answers from the island.
@MainActor
@Observable
final class AgentCenter {
    enum Decision: String, Sendable {
        case allow, deny, ask
    }

    /// What the hook hears back: the decision, and for the tools that need it (AskUserQuestion, ExitPlanMode) the
    /// input Allow approves, which the hook hands back to the agent.
    struct Answer: Sendable, Equatable {
        var decision: Decision
        var updatedInput: [String: JSONValue]? = nil
        /// What the agent reads when it is denied.
        var message: String? = nil

        var json: [String: Any] {
            var object: [String: Any] = ["decision": decision.rawValue]
            if let message { object["message"] = message }
            if let updatedInput, let data = try? JSONEncoder().encode(updatedInput),
               let input = try? JSONSerialization.jsonObject(with: data) {
                object["updatedInput"] = input
            }
            return object
        }
    }

    struct PendingRequest: Identifiable {
        var id: String
        var sessionID: String
        var project: String
        var agent: String?
        /// The tool, as people read its name.
        var tool: String
        /// What it is for, in a line: the command's first line for a shell, never the agent's description of it.
        var summary: String
        /// What Allow would approve, whole, as the card shows it: the command, file or address, or every argument.
        var detail: RequestDetail?
        var received: Date
        /// The tool the request is for, to recognise it once the tool has run.
        var toolName: String? = nil
        var toolInput: [String: JSONValue]? = nil
        /// A plan to approve, or questions to answer, rather than a tool to allow.
        var kind: Kind = .permission

        enum Kind: Equatable {
            case permission
            /// Claude Code leaves plan mode to carry out this plan, in Markdown, kept in this file.
            case plan(String, file: String?)
            /// Claude Code asks the user these questions; the island answers them.
            case questions([AgentQuestion])
        }
    }

    private(set) var board = AgentBoard()
    private(set) var pending: [String: PendingRequest] = [:]
    @ObservationIgnored private var responders: [String: @Sendable (Answer) -> Void] = [:]
    /// Where each session runs: its terminal and the processes above its hook, to bring them to the front.
    @ObservationIgnored private(set) var origins: [String: AgentOrigin] = [:]
    @ObservationIgnored private var settleTimer: Task<Void, Never>?
    @ObservationIgnored private var timeouts: [String: Task<Void, Never>] = [:]

    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when a request arrives, so the island can open and show it.
    @ObservationIgnored var onRequest: (() -> Void)?

    /// How long a permission request waits for the island before falling back to the terminal.
    static let answerWindow: Duration = .seconds(90)

    var sessions: [AgentSession] { board.ordered }

    func receive(_ event: HookEvent, respond: @escaping @Sendable (Decision) -> Void) {
        receive(event, origin: nil) { respond($0.decision) }
    }

    func receive(_ event: HookEvent, origin: AgentOrigin?, answer respond: @escaping @Sendable (Answer) -> Void) {
        let now = Date()
        board.apply(event, at: now)
        if event.event == "SessionEnd" || event.event == "End" {
            origins[event.sessionID] = nil
        } else if let origin {
            origins[event.sessionID] = origin
        }
        // Only agents whose hooks wait for an answer get the buttons; the others show they are waiting for the user.
        if event.event == "PermissionRequest", event.agent?.answersPermissions ?? true {
            let requestID = UUID().uuidString
            pending[requestID] = PendingRequest(
                id: requestID,
                sessionID: event.sessionID,
                project: event.project,
                agent: event.agent?.name,
                tool: event.toolLabel ?? "",
                summary: event.requestSummary ?? "",
                detail: event.toolDetail.map(RequestDetail.init),
                received: now,
                toolName: event.toolName,
                toolInput: event.toolInput,
                kind: event.plan.map { .plan($0, file: event.toolInput?["planFilePath"]?.string) }
                    ?? event.questions.map { .questions($0) } ?? .permission
            )
            responders[requestID] = respond
            timeouts[requestID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.answerWindow)
                guard !Task.isCancelled else { return }
                self?.resolve(requestID, .ask)
            }
            onRequest?()
        } else {
            respond(Answer(decision: .ask))
            if ["Stop", "SessionEnd", "UserPromptSubmit"].contains(event.event) {
                // The session moved on: a request it left behind was answered elsewhere.
                resolvePending(for: event.sessionID, .ask, updateBoard: false)
            } else if ["PostToolUse", "PostToolUseFailure"].contains(event.event) {
                // A tool that ran was allowed, in the island or in the terminal: its request, and only its, is over.
                resolveRequest(for: event, .ask)
            }
        }
        scheduleSettle()
        onChange?()
    }

    func decide(_ requestID: String, _ decision: Decision) {
        guard let request = pending[requestID] else { return }
        // Allow approves only what the island could show whole; anything longer is answered in the terminal. A plan is
        // approved as it was shown, its input handed back as it came.
        if case .plan = request.kind, decision != .ask {
            resolve(requestID, decision == .allow
                ? Answer(decision: .allow, updatedInput: Self.approving(request.toolInput))
                : Answer(decision: .deny, message: "The user chose to keep planning, from Col."))
        } else {
            resolve(requestID, Answer(decision: decision == .allow && !Self.canAllow(request) ? .ask : decision))
        }
        onChange?()
    }

    /// The input that approves a plan as it stands. Claude Code needs one beside `allow`, but takes a `plan` in it for
    /// the user's own edit of the plan, which would put the island's copy over edits made in the terminal meanwhile:
    /// the plan and its file are left out, and Claude Code keeps the plan of its file.
    static func approving(_ input: [String: JSONValue]?) -> [String: JSONValue] {
        (input ?? [:]).filter { $0.key != "plan" && $0.key != "planFilePath" }
    }

    /// Answers a request's questions with the labels chosen for each. Answers that are not among the options, or a
    /// question left without one, leave the request waiting.
    @discardableResult
    func answer(_ requestID: String, choices: [String: [String]]) -> Bool {
        guard let request = pending[requestID], case .questions = request.kind,
              let answered = AgentQuestion.answering(request.toolInput ?? [:], with: choices)
        else { return false }
        resolve(requestID, Answer(decision: .allow, updatedInput: answered))
        onChange?()
        return true
    }

    /// Whether the island may allow a request: what it approves fits the card, so it was seen whole. A request with
    /// input the card does not show is never allowed from it; only one that carries none is. A plan is shown whole, in
    /// a box that scrolls; questions are answered, never allowed as they stand.
    static func canAllow(_ request: PendingRequest) -> Bool {
        switch request.kind {
        case .plan: return true
        case .questions: return false
        case .permission: break
        }
        guard let detail = request.detail else { return request.toolInput?.isEmpty ?? true }
        return detail.fitsCard
    }

    private func resolve(_ requestID: String, _ decision: Decision, updateBoard: Bool = true) {
        resolve(requestID, Answer(decision: decision), updateBoard: updateBoard)
    }

    private func resolve(_ requestID: String, _ answer: Answer, updateBoard: Bool = true) {
        timeouts.removeValue(forKey: requestID)?.cancel()
        guard let request = pending.removeValue(forKey: requestID),
              let respond = responders.removeValue(forKey: requestID)
        else { return }
        respond(answer)
        if updateBoard, answer.decision != .ask {
            board.apply(HookEvent(sessionID: request.sessionID, event: "PreToolUse"), at: Date())
        }
    }

    /// The oldest request of the event's session for the same tool with the same input.
    private func resolveRequest(for event: HookEvent, _ decision: Decision) {
        let match = pending.values
            .filter { $0.sessionID == event.sessionID && $0.toolName == event.toolName && $0.toolInput == event.toolInput }
            .min { $0.received < $1.received }
        if let match { resolve(match.id, decision, updateBoard: false) }
    }

    private func resolvePending(for sessionID: String, _ decision: Decision, updateBoard: Bool) {
        let requestIDs = pending.values.filter { $0.sessionID == sessionID }.map(\.id)
        for requestID in requestIDs { resolve(requestID, decision, updateBoard: updateBoard) }
    }

    /// Finished sessions go quiet after a few seconds; one timer for all of them.
    private func scheduleSettle() {
        settleTimer?.cancel()
        guard board.sessions.values.contains(where: { $0.state == .done }) else { return }
        settleTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6.2))
            guard !Task.isCancelled, let self else { return }
            self.board.settle(now: Date())
            self.onChange?()
        }
    }

    func activity(tint: RGBA) -> Activity? {
        board.activity(now: Date(), tint: tint)
    }

    /// Focuses the terminal or editor a session runs in: the tab of its terminal, or the window of its folder, found
    /// from the processes its hook runs under; else the app most likely to hold it.
    func reveal(_ session: AgentSession) {
        if let origin = origins[session.id], AgentReveal.reveal(origin) { return }
        if session.agent == CodingAgent.cursor.name,
           let cursor = NSRunningApplication.runningApplications(withBundleIdentifier: "com.todesktop.230313mzl4w4u92").first {
            cursor.activate()
            return
        }
        for bundle in Self.revealCandidates(for: session) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
                app.activate()
                return
            }
            if session.agent == CodingAgent.copilot.name,
               bundle == "com.microsoft.VSCode" || bundle == "com.microsoft.VSCodeInsiders",
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                return
            }
        }
    }

    /// Brings forward the terminal or editor of the session with this id.
    func revealSession(_ id: String) {
        if let session = board.sessions[id] {
            reveal(session)
        } else if let origin = origins[id] {
            AgentReveal.reveal(origin)
        }
    }

    static func revealCandidates(for session: AgentSession) -> [String] {
        let fallback = ["com.anthropic.claudefordesktop", "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal", "com.microsoft.VSCode", "dev.warp.Warp-Stable"]
        guard session.agent == CodingAgent.copilot.name else { return fallback }
        return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"] + fallback.filter { $0 != "com.microsoft.VSCode" }
    }
}

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

    struct PendingRequest: Identifiable {
        var id: String
        var sessionID: String
        var project: String
        var agent: String?
        /// The tool, as people read its name.
        var tool: String
        /// What it is for, in a line: the command's first line for a shell, never the agent's description of it.
        var summary: String
        /// The whole command, file or address Allow would approve, as the card shows it.
        var detail: RequestDetail?
        var received: Date
        /// The tool the request is for, to recognise it once the tool has run.
        var toolName: String? = nil
        var toolInput: [String: JSONValue]? = nil
    }

    private(set) var board = AgentBoard()
    private(set) var pending: [String: PendingRequest] = [:]
    @ObservationIgnored private var responders: [String: @Sendable (Decision) -> Void] = [:]
    @ObservationIgnored private var settleTimer: Task<Void, Never>?
    @ObservationIgnored private var timeouts: [String: Task<Void, Never>] = [:]

    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when a request arrives, so the island can open and show it.
    @ObservationIgnored var onRequest: (() -> Void)?

    /// How long a permission request waits for the island before falling back to the terminal.
    static let answerWindow: Duration = .seconds(90)

    var sessions: [AgentSession] { board.ordered }

    func receive(_ event: HookEvent, respond: @escaping @Sendable (Decision) -> Void) {
        let now = Date()
        board.apply(event, at: now)
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
                toolInput: event.toolInput
            )
            responders[requestID] = respond
            timeouts[requestID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.answerWindow)
                guard !Task.isCancelled else { return }
                self?.resolve(requestID, .ask)
            }
            onRequest?()
        } else {
            respond(.ask)
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
        // Allow approves only what the island could show whole; anything longer is answered in the terminal.
        let allowed = pending[requestID].map(Self.canAllow) ?? false
        resolve(requestID, decision == .allow && !allowed ? .ask : decision)
        onChange?()
    }

    /// Whether the island may allow a request: its command, file or address fits the card, so it was seen whole.
    static func canAllow(_ request: PendingRequest) -> Bool {
        request.detail?.fitsCard ?? true
    }

    private func resolve(_ requestID: String, _ decision: Decision, updateBoard: Bool = true) {
        timeouts.removeValue(forKey: requestID)?.cancel()
        guard let request = pending.removeValue(forKey: requestID),
              let respond = responders.removeValue(forKey: requestID)
        else { return }
        respond(decision)
        if updateBoard, decision != .ask {
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

    /// Focuses the terminal or editor a session runs in, by its folder when possible.
    func reveal(_ session: AgentSession) {
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

    static func revealCandidates(for session: AgentSession) -> [String] {
        let fallback = ["com.anthropic.claudefordesktop", "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal", "com.microsoft.VSCode", "dev.warp.Warp-Stable"]
        guard session.agent == CodingAgent.copilot.name else { return fallback }
        return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"] + fallback.filter { $0 != "com.microsoft.VSCode" }
    }
}

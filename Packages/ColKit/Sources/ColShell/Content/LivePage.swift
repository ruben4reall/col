import ColCore
import SwiftUI

/// Everything running: agent sessions, their permission requests, and activities pushed by other programs.
struct LivePage: View {
    let agents: AgentCenter
    let custom: CustomActivities

    var body: some View {
        let sessions = agents.sessions
        // Oldest first: a request that arrives goes below the others, never under the pointer about to answer one.
        let requests = agents.pending.values.sorted { ($0.received, $0.id) < ($1.received, $1.id) }
        let sessionsWithRequests = Set(requests.map(\.sessionID))
        if sessions.isEmpty && custom.entries.isEmpty {
            EmptyLive()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(Array(requests.enumerated()), id: \.element.id) { position, request in
                        PermissionCard(request: request, position: position) { agents.decide(request.id, $0) }
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                    ForEach(sessions.filter { !sessionsWithRequests.contains($0.id) }) { session in
                        AgentRow(session: session) { agents.reveal(session) }
                    }
                    ForEach(custom.entries) { entry in
                        ActivityRow(entry: entry)
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.15), value: requests.map(\.id))
            }
        }
    }
}

/// Which agent a session belongs to, when several are connected.
private struct AgentTag: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .fixedSize()
    }
}

private struct EmptyLive: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text("Nothing running", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Agents and anything you push with the colctl command show up here.", bundle: .module)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A request to answer. The header names the tool; below it, what Allow approves, whole and as it is: the exact
/// command, file or address, or every argument of any other tool, each invisible character shown (RequestDetail). One
/// too long to check here says so in place of the tool's name, and can only be answered in the terminal, which shows
/// it whole.
private struct PermissionCard: View {
    let request: AgentCenter.PendingRequest
    /// Its place among the requests: when it changes, the card has moved under the pointer.
    let position: Int
    let decide: (AgentCenter.Decision) -> Void
    /// Allow waits a moment after the card appears or moves, so a click meant for another card never lands on it.
    @State private var armed = false

    private typealias Layout = PermissionCardLayout
    private static let box = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        let canAllow = AgentCenter.canAllow(request)
        let tooLong = request.detail.map { !$0.fitsCard } ?? false
        VStack(alignment: .leading, spacing: Layout.spacing) {
            HStack(spacing: 8) {
                // The agent's own logo, a small hand in its corner: it is asking.
                AppIconView(icon: CodingAgent.icon(for: request.agent), size: Layout.headerHeight)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(.orange))
                            .background(Circle().stroke(Color.black, lineWidth: 2))
                            .offset(x: 3, y: 3)
                    }
                Text(request.project)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let agent = request.agent { AgentTag(name: agent) }
                if tooLong {
                    // Still all there below, to read or copy, but past what can be checked at a glance.
                    Text("Too long to check here", bundle: .module)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .layoutPriority(1)
                } else {
                    // With the detail below, the tool's name is enough: the detail says the rest, exactly.
                    Text(request.detail == nil ? request.summary : request.tool)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let detail = request.detail {
                if detail.fitsCard {
                    exact(detail)
                        .background(Self.box.fill(Color.white.opacity(0.06)))
                } else {
                    // A few lines at a time, so that the buttons stay in sight on the page.
                    ScrollView(.vertical) { exact(detail) }
                        .frame(height: Layout.textHeight(lines: Layout.scrollingLines))
                        .background(Self.box.fill(Color.white.opacity(0.06)))
                        .clipShape(Self.box)
                }
            }
            HStack(spacing: 8) {
                DecisionButton(title: Text("Allow", bundle: .module), prominent: true, enabled: canAllow) { decide(.allow) }
                    .disabled(!armed)
                DecisionButton(title: Text("Deny", bundle: .module), prominent: false) { decide(.deny) }
                Spacer(minLength: 0)
                Button {
                    decide(.ask)
                } label: {
                    Text("Answer in terminal", bundle: .module)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(canAllow ? Theme.secondaryText : .white)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(Layout.padding)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.orange.opacity(0.1))
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .task(id: Placement(id: request.id, position: position)) {
            armed = false
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { armed = true }
        }
    }

    /// The text Allow approves, never cut: no line limit, and as many lines as it needs.
    private func exact(_ detail: RequestDetail) -> some View {
        Text(verbatim: detail.shown)
            .font(.system(size: Layout.fontSize, design: .monospaced))
            .foregroundStyle(.white.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(Layout.textInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Placement: Equatable {
        var id: String
        var position: Int
    }
}

/// The Allow card's measures, which what it may approve counts on: RequestDetail.columns is what a line of its text
/// holds in the compact island, and the card keeps its buttons in sight on the page with up to RequestDetail.lines of
/// it, or `scrollingLines` of one too long to check.
enum PermissionCardLayout {
    static let padding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    static let spacing: CGFloat = 6
    static let headerHeight: CGFloat = 22
    static let buttonHeight: CGFloat = 26
    /// The command's text: 11-point SF Mono, 14 points a line as SwiftUI sets it, inset in its box.
    static let fontSize: CGFloat = 11
    static let lineHeight: CGFloat = 14
    static let textInset = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
    /// Lines the box shows of a request too long to check here; the rest scrolls.
    static let scrollingLines = 2

    static func textHeight(lines: Int) -> CGFloat {
        CGFloat(lines) * lineHeight + textInset.top + textInset.bottom
    }

    /// Room for a line of the command's text in an island of this size.
    static func textWidth(in size: IslandSize) -> CGFloat {
        size.open.width - Theme.inset.leading - Theme.inset.trailing - padding.leading - padding.trailing
            - textInset.leading - textInset.trailing
    }

    /// From the top of the card to the bottom of its buttons, with this many lines of text.
    static func buttonsBottom(lines: Int) -> CGFloat {
        padding.top + headerHeight + spacing + textHeight(lines: lines) + spacing + buttonHeight
    }
}

private struct DecisionButton: View {
    let title: Text
    let prominent: Bool
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let lit = hovering && enabled
        Button(action: action) {
            title
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 14)
                .frame(height: PermissionCardLayout.buttonHeight)
                .background(Capsule().fill(prominent ? Color.white.opacity(lit ? 0.85 : 1) : Color.white.opacity(lit ? 0.2 : 0.13)))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
    }
}

private struct AgentRow: View {
    let session: AgentSession
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            HStack(spacing: 10) {
                AppIconView(icon: CodingAgent.icon(for: session.agent), size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(session.project)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                        if let agent = session.agent { AgentTag(name: agent) }
                    }
                    status
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isWorking {
                    Text(session.since, style: .timer)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var isWorking: Bool {
        if case .working = session.state { return true }
        return false
    }

    @ViewBuilder private var status: some View {
        switch session.state {
        case .idle: Text("Idle", bundle: .module)
        case .working(let detail): Text(detail ?? String(localized: "Working", bundle: .module))
        case .waiting(let detail): Text(detail ?? String(localized: "Waiting for you", bundle: .module)).foregroundStyle(.orange)
        case .done: Text("Done", bundle: .module).foregroundStyle(RGBA.green.color)
        }
    }
}

private struct ActivityRow: View {
    let entry: CustomActivities.Entry

    var body: some View {
        let request = entry.request
        let tint = request.resolvedTint.color
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: entry.finished ? "checkmark" : (request.symbol ?? "circle.hexagongrid.fill"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(entry.finished ? RGBA.green.color : tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(request.title ?? request.id)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 4)
                    if let text = request.text {
                        Text(text)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    } else if let progress = request.progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                if let subtitle = request.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                if let progress = request.progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(tint).frame(width: max(4, geometry.size.width * progress))
                        }
                    }
                    .frame(height: 4)
                    .animation(.spring(duration: 0.4, bounce: 0), value: progress)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.fill))
    }
}

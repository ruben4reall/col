import IsletCore
import SwiftUI

/// Everything running: agent sessions, their permission requests, and activities pushed by other programs.
struct LivePage: View {
    let agents: AgentCenter
    let custom: CustomActivities

    var body: some View {
        let sessions = agents.sessions
        let requests = agents.pending.values.sorted { $0.received > $1.received }
        let sessionsWithRequests = Set(requests.map(\.sessionID))
        if sessions.isEmpty && custom.entries.isEmpty {
            EmptyLive()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(requests) { request in
                        PermissionCard(request: request) { agents.decide(request.id, $0) }
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
                .foregroundStyle(Theme.coral.color)
            Text("Nothing running", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Agents and anything you push with the islet command show up here.", bundle: .module)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PermissionCard: View {
    let request: AgentCenter.PendingRequest
    let decide: (AgentCenter.Decision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Text(request.project)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                if let agent = request.agent { AgentTag(name: agent) }
                Text(request.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let detail = request.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            }
            HStack(spacing: 8) {
                DecisionButton(title: Text("Allow", bundle: .module), prominent: true) { decide(.allow) }
                DecisionButton(title: Text("Deny", bundle: .module), prominent: false) { decide(.deny) }
                Spacer(minLength: 0)
                Button {
                    decide(.ask)
                } label: {
                    Text("Answer in terminal", bundle: .module)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.orange.opacity(0.1))
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct DecisionButton: View {
    let title: Text
    let prominent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            title
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.85 : 1) : Color.white.opacity(hovering ? 0.2 : 0.13)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }
}

private struct AgentRow: View {
    let session: AgentSession
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.coral.color.opacity(0.15))
                    Image(systemName: CodingAgent.symbol(for: session.agent))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.coral.color)
                        .symbolEffect(.pulse, isActive: isWorking)
                }
                .frame(width: 28, height: 28)
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

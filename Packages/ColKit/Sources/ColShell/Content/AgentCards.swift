import AppKit
import ColCore
import SwiftUI

/// Claude Code asks to leave plan mode and carry out a plan: the plan itself, read as Markdown in a box that scrolls and
/// can be selected, with Approve and Keep Planning beside the agent's name, always in sight.
struct PlanCard: View {
    let request: AgentCenter.PendingRequest
    let plan: String
    let file: String?
    let position: Int
    let decide: (AgentCenter.Decision) -> Void
    @State private var armed = false

    private typealias Layout = PermissionCardLayout

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            HStack(spacing: 8) {
                AgentBadge(agent: request.agent, symbol: "list.bullet.clipboard.fill", tint: .blue)
                Text(request.project)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Plan", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                DecisionButton(title: Text("Approve", bundle: .module), prominent: true) { decide(.allow) }
                    .disabled(!armed)
                DecisionButton(title: Text("Keep Planning", bundle: .module), prominent: false) { decide(.deny) }
            }
            ScrollView(.vertical) {
                MarkdownText(markdown: plan)
                    .padding(Layout.textInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Layout.textHeight(lines: Layout.planLines))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let file, Self.canOpen(file) {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: file))
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(6)
                    }
                    .buttonStyle(PressableStyle())
                    .help(Text("Open the plan’s file", bundle: .module))
                }
            }
        }
        .padding(Layout.padding)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.blue.opacity(0.1))
                .strokeBorder(Color.blue.opacity(0.35), lineWidth: 1)
        )
        .task(id: [request.id, String(position)]) {
            armed = false
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { armed = true }
        }
    }

    /// Only a Markdown file Claude Code keeps its plans in, in the user's own folders.
    static func canOpen(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return url.pathExtension == "md" && url.path.hasPrefix(NSHomeDirectory() + "/") && url.path.contains("/plans/")
            && FileManager.default.isReadableFile(atPath: url.path)
    }
}

/// Claude Code asks questions: each one with its options. With a single question of a single choice, the option
/// answers at once; otherwise options are picked, then sent. Answer in Terminal leaves them to the terminal and brings
/// it forward.
struct QuestionCard: View {
    let request: AgentCenter.PendingRequest
    let questions: [AgentQuestion]
    let position: Int
    let send: ([String: [String]]) -> Void
    let inTerminal: () -> Void
    @State private var choices: [String: [String]] = [:]
    @State private var armed = false

    private typealias Layout = PermissionCardLayout

    /// One question, one choice: an option is the answer.
    private var answersAtOnce: Bool { questions.count == 1 && !questions[0].multiSelect }

    private var complete: Bool {
        questions.allSatisfy { !(choices[$0.question] ?? []).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            HStack(spacing: 8) {
                AgentBadge(agent: request.agent, symbol: "questionmark", tint: .purple)
                Text(request.project)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let header = questions.first?.header, questions.count == 1 {
                    AgentTag(name: header)
                }
                Spacer(minLength: 4)
                if !answersAtOnce {
                    DecisionButton(title: Text("Send", bundle: .module), prominent: true, enabled: complete) { send(choices) }
                        .disabled(!armed)
                }
                Button(action: inTerminal) {
                    Text("Answer in Terminal", bundle: .module)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(PressableStyle())
            }
            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: question.question)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    FlowLayout(spacing: 6) {
                        ForEach(question.options, id: \.label) { option in
                            OptionChip(option: option, selected: (choices[question.question] ?? []).contains(option.label),
                                       multiple: question.multiSelect) {
                                pick(option.label, in: question)
                            }
                            .disabled(!armed)
                        }
                    }
                }
            }
        }
        .padding(Layout.padding)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.purple.opacity(0.12))
                .strokeBorder(Color.purple.opacity(0.4), lineWidth: 1)
        )
        .task(id: [request.id, String(position)]) {
            armed = false
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { armed = true }
        }
    }

    private func pick(_ label: String, in question: AgentQuestion) {
        var chosen = choices[question.question] ?? []
        if question.multiSelect {
            if let index = chosen.firstIndex(of: label) { chosen.remove(at: index) } else { chosen.append(label) }
        } else {
            chosen = [label]
        }
        choices[question.question] = chosen
        if answersAtOnce { send(choices) }
    }
}

/// The agent's logo with a sign in its corner, saying what it asks for.
private struct AgentBadge: View {
    let agent: String?
    let symbol: String
    let tint: Color

    var body: some View {
        AppIconView(icon: CodingAgent.icon(for: agent), size: PermissionCardLayout.headerHeight)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(tint))
                    .background(Circle().stroke(Color.black, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
    }
}

private struct OptionChip: View {
    let option: AgentQuestion.Option
    let selected: Bool
    let multiple: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if multiple {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(verbatim: option.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? .black : .white)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(hovering ? 0.2 : 0.13)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(Text(verbatim: option.detail ?? option.label))
    }
}

/// Views side by side, going to the next line when the line is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(size.width, width)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + itemWidth > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// Markdown as a plan is written: headings, paragraphs, lists, quotes, code and rules, each block's emphasis, code
/// and links read inline. Selectable; links open only on the web.
struct MarkdownText: View {
    let markdown: String
    var size: CGFloat = 11.5

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(MarkdownDocument.blocks(markdown).enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { AskSession.opensOnTheWeb($0) ? .systemAction : .discarded })
    }

    @ViewBuilder private func view(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(.system(size: level == 1 ? size + 3 : level == 2 ? size + 1.5 : size, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            inline(text)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.85))
        case .item(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: marker)
                    .font(.system(size: size, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                inline(text)
                    .font(.system(size: size))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.leading, CGFloat(depth) * 12)
        case .quote(let text):
            inline(text)
                .font(.system(size: size))
                .foregroundStyle(Theme.secondaryText)
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Capsule().fill(Theme.tertiaryText).frame(width: 2) }
        case .code(let code):
            Text(verbatim: code)
                .font(.system(size: size - 1, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
        case .rule:
            Rectangle().fill(Theme.tertiaryText).frame(height: 1)
        }
    }

    private func inline(_ text: String) -> Text {
        Text(AskSession.markdown(text))
    }
}

import AppKit
import ColCore
import SwiftUI

/// Asking one of your own models from the island: a field at the foot of the AI page. The island takes the keyboard
/// only while the field is in use, and gives it back on Escape, on Return with nothing typed, or when it closes.
struct AskBar: View {
    let ai: AIAppsModel
    let choices: [AskSession.Choice]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let session = ai.ask
        HStack(spacing: 8) {
            ModelMenu(session: session, choices: choices)
            Group {
                if session.editing {
                    TextField(text: $text, prompt: prompt(session)) { EmptyView() }
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(send)
                        .onExitCommand(perform: endEditing)
                } else {
                    // A plain button until the field is needed: the island lends no keyboard before.
                    Button(action: beginEditing) {
                        prompt(session).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .help(Text("Your question goes only to \(session.choice?.server.name ?? "")", bundle: .module))
            if session.streaming {
                RoundButton(symbol: "stop.fill", label: Text("Stop", bundle: .module), prominent: false) { session.stop() }
            } else {
                RoundButton(symbol: "arrow.up", label: Text("Send", bundle: .module), prominent: !text.isEmpty, action: send)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 3)
        .frame(height: 32)
        .background(Capsule().fill(Theme.fill))
        .onAppear {
            // The page became the conversation while typing: the new field takes the focus back.
            if session.editing { DispatchQueue.main.async { focused = true } }
        }
    }

    private func prompt(_ session: AskSession) -> Text {
        let model = session.choice?.model ?? ""
        return session.messages.isEmpty
            ? Text("Ask \(model)…", bundle: .module).foregroundStyle(Theme.secondaryText)
            : Text("Ask a follow-up…", bundle: .module).foregroundStyle(Theme.secondaryText)
    }

    private func beginEditing() {
        IslandController.shared?.takeKeyboard()
        ai.ask.editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func endEditing() {
        focused = false
        ai.ask.editing = false
        IslandController.shared?.releaseKeyboard()
    }

    private func send() {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return endEditing() }
        ai.ask.ask(question)
        text = ""
    }
}

/// The conversation, in place of the apps while it is on: each question small, each answer as the model writes it.
struct AskConversation: View {
    let ai: AIAppsModel
    let choices: [AskSession.Choice]

    var body: some View {
        let session = ai.ask
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                            if message.role == .user {
                                Text(verbatim: message.text)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(2)
                            } else {
                                Answer(text: message.text, streaming: session.streaming)
                            }
                        }
                        if let failure = session.failure {
                            Text(verbatim: failure).font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                // Earlier lines fade under the top edge instead of being cut.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.32)],
                                     startPoint: .top, endPoint: .bottom))
                .onChange(of: session.messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if session.lastAnswer != nil, !session.streaming {
                        IslandChip(symbol: "doc.on.doc", title: nil) { session.copyAnswer() }
                            .help(Text("Copy the Answer", bundle: .module))
                            .accessibilityLabel(Text("Copy the Answer", bundle: .module))
                    }
                    IslandChip(symbol: "square.and.pencil", title: nil) { session.clear() }
                        .help(Text("New Conversation", bundle: .module))
                        .accessibilityLabel(Text("New Conversation", bundle: .module))
                }
            }
            AskBar(ai: ai, choices: choices)
        }
    }
}

/// An answer: Markdown read for emphasis and code, a model's thinking aloud kept out of sight.
private struct Answer: View {
    let text: String
    let streaming: Bool

    var body: some View {
        let shown = AskSession.shown(text)
        VStack(alignment: .leading, spacing: 6) {
            if !shown.text.isEmpty {
                Text(Self.markdown(shown.text))
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.trailing, 64)
            }
            if streaming, shown.thinking || shown.text.isEmpty {
                HStack(spacing: 6) {
                    PulsingDots(color: NSColor(white: 0.92, alpha: 0.6), dot: 4, spacing: 3)
                    Text("Thinking…", bundle: .module)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Which model answers: the server's icon and the model's name; the menu lists every model that can answer now.
private struct ModelMenu: View {
    let session: AskSession
    let choices: [AskSession.Choice]
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(servers, id: \.id) { server in
                Section(server.name) {
                    ForEach(choices.filter { $0.server.id == server.id }, id: \.self) { choice in
                        Button { session.choice = choice } label: {
                            if choice == session.choice { Label(choice.model, systemImage: "checkmark") } else { Text(verbatim: choice.model) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let server = session.choice?.server {
                    AppIconView(icon: AppIcon(bundleIdentifiers: server.kind.icon.bundleIdentifiers, name: server.kind.icon.name,
                                              mark: server.kind.icon.mark, symbol: "cpu", tint: server.kind.icon.tint), size: 18)
                }
                Text(verbatim: session.choice?.model ?? "")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Capsule().fill(.white.opacity(hovering ? 0.16 : 0.1)))
            .contentShape(Capsule())
            .onHover { hovering = $0 }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Model", bundle: .module))
    }

    /// The servers that have a model to offer, in their order.
    private var servers: [ModelServer] {
        var seen: [ModelServer] = []
        for choice in choices where !seen.contains(choice.server) { seen.append(choice.server) }
        return seen
    }
}

/// A round button at the end of the field: Send, white once there is something to send, or Stop.
private struct RoundButton: View {
    let symbol: String
    let label: Text
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(prominent ? .black : .white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(prominent ? Color.white : Color.white.opacity(0.14)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

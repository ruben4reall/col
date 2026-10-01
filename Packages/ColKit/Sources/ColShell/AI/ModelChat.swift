import Foundation
import ColCore

/// Talks with a model of the user's own servers, the answer arriving word by word. Ollama speaks its own chat API;
/// LM Studio, llama.cpp and every OpenAI-compatible server speak OpenAI's. Nothing goes anywhere else.
enum ModelChat {
    struct Message: Equatable, Sendable {
        enum Role: String, Sendable { case user, assistant }
        var role: Role
        var text: String
    }

    enum Failure: Error, Equatable {
        case unreachable
        case refused(Int)
    }

    /// Streams the answer to a conversation, piece by piece.
    static func answer(_ messages: [Message], model: String, server: ModelServer, token: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: server.address.appendingPathComponent(server.kind == .ollama ? "api/chat" : "v1/chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    request.timeoutInterval = 120
                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw Failure.unreachable }
                    guard (200..<300).contains(http.statusCode) else { throw Failure.refused(http.statusCode) }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let piece = server.kind == .ollama ? ollamaPiece(line) : openAIPiece(line) {
                            continuation.yield(piece)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One line of Ollama's stream: `{"message":{"content":"…"},"done":false}`.
    static func ollamaPiece(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? String, !content.isEmpty
        else { return nil }
        return content
    }

    /// One line of an OpenAI stream: `data: {"choices":[{"delta":{"content":"…"}}]}`, and `data: [DONE]` at the end.
    static func openAIPiece(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (object["choices"] as? [[String: Any]])?.first,
              let delta = choice["delta"] as? [String: Any],
              let content = delta["content"] as? String, !content.isEmpty
        else { return nil }
        return content
    }
}

import Foundation
import ColCore

/// Asks model servers what they hold. Short timeouts: a server that does not answer within a moment is down for now.
actor ModelServerClient {
    static let shared = ModelServerClient()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2.5
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// What a server holds now, read from the endpoints its kind has.
    func status(of server: ModelServer, token: String?) async -> ModelServerStatus {
        switch server.kind {
        case .ollama:
            guard let tags = await get(server.address, "api/tags", token), let models = ModelServerReply.ollamaModels(tags) else { return .unreachable }
            let loaded = await get(server.address, "api/ps", token).flatMap(ModelServerReply.ollamaLoaded) ?? []
            return ModelServerStatus(reachable: true, models: models, loaded: loaded)
        case .lmStudio:
            guard let data = await get(server.address, "api/v0/models", token), let reply = ModelServerReply.lmStudioModels(data) else {
                // LM Studio's own endpoint can be off: the OpenAI one still says it is up.
                return await openAI(server, token)
            }
            return ModelServerStatus(reachable: true, models: reply.models, loaded: reply.loaded)
        case .llamaCpp:
            var status = await openAI(server, token)
            guard status.reachable else { return status }
            // llama.cpp serves the model it was started with: it is loaded, and its slots say when it works.
            status.loaded = status.models.map { LoadedModel(name: $0) }
            status.generating = await get(server.address, "slots", token).flatMap(ModelServerReply.llamaCppGenerating)
            return status
        case .openAI:
            return await openAI(server, token)
        }
    }

    /// The kind of server at an address, tried from the most telling to the most common.
    func detect(_ address: URL, token: String?) async -> ModelServerKind? {
        if await get(address, "api/version", token) != nil, await get(address, "api/tags", token).flatMap(ModelServerReply.ollamaModels) != nil {
            return .ollama
        }
        if await get(address, "api/v0/models", token).flatMap(ModelServerReply.lmStudioModels) != nil { return .lmStudio }
        if await get(address, "slots", token).flatMap(ModelServerReply.llamaCppGenerating) != nil { return .llamaCpp }
        if await get(address, "v1/models", token).flatMap(ModelServerReply.openAIModels) != nil { return .openAI }
        return nil
    }

    private func openAI(_ server: ModelServer, _ token: String?) async -> ModelServerStatus {
        guard let data = await get(server.address, "v1/models", token), let models = ModelServerReply.openAIModels(data) else { return .unreachable }
        return ModelServerStatus(reachable: true, models: models)
    }

    private func get(_ base: URL, _ path: String, _ token: String?) async -> Data? {
        var request = URLRequest(url: base.appendingPathComponent(path))
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }
}

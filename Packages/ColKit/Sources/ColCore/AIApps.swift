import Foundation

/// An AI app Col recognizes on the Mac, by its bundle identifiers.
public struct AIApp: Sendable, Identifiable, Equatable {
    public enum Role: String, Sendable {
        /// A chat assistant: Claude, ChatGPT, Perplexity…
        case assistant
        /// An editor or agent for code: Cursor, VS Code with Copilot…
        case coding
        /// Runs models on the Mac: Ollama, LM Studio…
        case models
    }

    public let id: String
    public let name: String
    public let bundleIdentifiers: [String]
    public let role: Role
    /// The coding agent whose hooks Col connects to through this app, if any.
    public let agent: CodingAgent?
    /// The model server the app runs on this Mac, if any.
    public let server: ModelServerKind?
    /// The brand's logo Col carries, shown when the app is not installed.
    public let mark: String?

    public init(id: String, name: String, bundleIdentifiers: [String], role: Role, agent: CodingAgent? = nil, server: ModelServerKind? = nil,
                mark: String? = nil) {
        self.id = id
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.role = role
        self.agent = agent
        self.server = server
        self.mark = mark
    }
}

/// The AI apps Col knows. Identifiers as the apps ship them in 2026 (ChatGPT took Codex's identifier when the two
/// apps merged); several per app when an app changed its identifier or has editions.
public enum AICatalog {
    public static let apps: [AIApp] = [
        AIApp(id: "claude", name: "Claude", bundleIdentifiers: ["com.anthropic.claudefordesktop"], role: .assistant, agent: .claude, mark: "claude"),
        AIApp(id: "chatgpt", name: "ChatGPT", bundleIdentifiers: ["com.openai.codex", "com.openai.chat"], role: .assistant, agent: .codex, mark: "openai"),
        AIApp(id: "gemini", name: "Gemini", bundleIdentifiers: ["com.google.GeminiMacOS"], role: .assistant, agent: .gemini, mark: "gemini"),
        AIApp(id: "perplexity", name: "Perplexity", bundleIdentifiers: ["ai.perplexity.macv3", "ai.perplexity.comet"], role: .assistant, mark: "perplexity"),
        AIApp(id: "grok", name: "Grok Bot", bundleIdentifiers: ["com.anysphere.sand"], role: .assistant, mark: "grok"),
        AIApp(id: "copilot", name: "Copilot", bundleIdentifiers: ["com.microsoft.m365copilot", "com.github.githubapp"], role: .assistant, mark: "copilot"),
        AIApp(id: "raycast", name: "Raycast", bundleIdentifiers: ["com.raycast.macos"], role: .assistant),
        AIApp(id: "kimi", name: "Kimi", bundleIdentifiers: ["com.moonshot.kimichat"], role: .assistant, mark: "kimi"),
        AIApp(id: "manus", name: "Manus", bundleIdentifiers: ["im.manus.desktop"], role: .assistant, mark: "manus"),
        AIApp(id: "cursor", name: "Cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], role: .coding, agent: .cursor, mark: "cursor"),
        AIApp(id: "vscode", name: "VS Code", bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], role: .coding, agent: .copilot),
        AIApp(id: "devin", name: "Devin Desktop", bundleIdentifiers: ["com.exafunction.windsurf"], role: .coding, mark: "devin"),
        AIApp(id: "zed", name: "Zed", bundleIdentifiers: ["dev.zed.Zed"], role: .coding),
        AIApp(id: "kiro", name: "Kiro", bundleIdentifiers: ["dev.kiro.desktop"], role: .coding, mark: "kiro"),
        AIApp(id: "antigravity", name: "Antigravity", bundleIdentifiers: ["com.google.antigravity"], role: .coding),
        AIApp(id: "trae", name: "Trae", bundleIdentifiers: ["com.trae.app"], role: .coding, mark: "trae"),
        AIApp(id: "opencode", name: "OpenCode", bundleIdentifiers: ["ai.opencode.desktop"], role: .coding, mark: "opencode"),
        AIApp(id: "amp", name: "Amp", bundleIdentifiers: ["com.ampcode.amp.macos"], role: .coding, mark: "amp"),
        AIApp(id: "ollama", name: "Ollama", bundleIdentifiers: ["com.electron.ollama"], role: .models, server: .ollama, mark: "ollama"),
        AIApp(id: "lmstudio", name: "LM Studio", bundleIdentifiers: ["ai.elementlabs.lmstudio"], role: .models, server: .lmStudio, mark: "lmstudio"),
        AIApp(id: "msty", name: "Msty", bundleIdentifiers: ["app.msty.app"], role: .models),
        AIApp(id: "jan", name: "Jan", bundleIdentifiers: ["jan.ai.app"], role: .models),
        AIApp(id: "gpt4all", name: "GPT4All", bundleIdentifiers: ["com.nomic-ai.gpt4all"], role: .models),
        AIApp(id: "osaurus", name: "Osaurus", bundleIdentifiers: ["com.dinoki.osaurus"], role: .models),
    ]

    public static func app(_ id: String) -> AIApp? {
        apps.first { $0.id == id }
    }

    /// The app a bundle identifier belongs to.
    public static func app(bundleIdentifier: String) -> AIApp? {
        apps.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }
}

// MARK: Model servers

/// The kinds of model servers Col can read. Each says what it can tell: every one lists its models; Ollama and LM
/// Studio say which are loaded; llama.cpp also says when a model is generating.
public enum ModelServerKind: String, Codable, CaseIterable, Sendable {
    case ollama, lmStudio, llamaCpp, openAI

    public var name: String {
        switch self {
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .llamaCpp: "llama.cpp"
        case .openAI: "OpenAI-compatible"
        }
    }

    /// Where the server listens on the Mac that runs it, out of the box.
    public var defaultPort: Int {
        switch self {
        case .ollama: 11434
        case .lmStudio: 1234
        case .llamaCpp: 8080
        case .openAI: 8000
        }
    }
}

/// A model server Col watches: one of the Mac's own apps, or one the user added, on this Mac or another machine.
public struct ModelServer: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: ModelServerKind
    /// The server's base address, such as `http://192.168.1.20:11434`.
    public var address: URL
    /// A token is kept in the Keychain for it, sent as `Authorization: Bearer`.
    public var usesToken: Bool

    public init(id: String = UUID().uuidString, name: String, kind: ModelServerKind, address: URL, usesToken: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.address = address
        self.usesToken = usesToken
    }

    /// The address a user typed, completed: a scheme when it has none, the kind's port when it has none.
    public static func address(from text: String, kind: ModelServerKind?) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty,
              components.scheme == "http" || components.scheme == "https"
        else { return nil }
        if components.port == nil, let kind { components.port = kind.defaultPort }
        components.path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// True for a server on this Mac.
    public var isLocal: Bool {
        guard let host = address.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

/// A model that sits in memory, ready to answer.
public struct LoadedModel: Equatable, Sendable {
    public var name: String
    /// Bytes it holds in the graphics memory, when the server says.
    public var memory: Int64?

    public init(name: String, memory: Int64? = nil) {
        self.name = name
        self.memory = memory
    }
}

/// What a server said the last time it was asked.
public struct ModelServerStatus: Equatable, Sendable {
    public var reachable: Bool
    public var models: [String]
    public var loaded: [LoadedModel]
    /// Whether a model is generating now; nil when the server cannot tell.
    public var generating: Bool?

    public init(reachable: Bool, models: [String] = [], loaded: [LoadedModel] = [], generating: Bool? = nil) {
        self.reachable = reachable
        self.models = models
        self.loaded = loaded
        self.generating = generating
    }

    public static let unreachable = ModelServerStatus(reachable: false)
}

/// Reads what model servers answer. Each reader takes the body of one endpoint and keeps what Col shows.
public enum ModelServerReply {
    /// Ollama `/api/tags`: the models installed.
    public static func ollamaModels(_ data: Data) -> [String]? {
        struct Reply: Decodable { struct Model: Decodable { var name: String }; var models: [Model] }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.models.map(\.name)
    }

    /// Ollama `/api/ps`: the models in memory, with the memory they hold.
    public static func ollamaLoaded(_ data: Data) -> [LoadedModel]? {
        struct Reply: Decodable { struct Model: Decodable { var name: String; var size_vram: Int64? }; var models: [Model] }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.models.map { LoadedModel(name: $0.name, memory: $0.size_vram) }
    }

    /// LM Studio `/api/v0/models`: every model, and its state.
    public static func lmStudioModels(_ data: Data) -> (models: [String], loaded: [LoadedModel])? {
        struct Reply: Decodable { struct Model: Decodable { var id: String; var state: String?; var type: String? }; var data: [Model] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        let models = reply.data.filter { $0.type != "embeddings" }
        return (models.map(\.id), models.filter { $0.state == "loaded" }.map { LoadedModel(name: $0.id) })
    }

    /// llama.cpp `/slots`: a slot at work means a model is generating.
    public static func llamaCppGenerating(_ data: Data) -> Bool? {
        struct Slot: Decodable { var is_processing: Bool? }
        guard let slots = try? JSONDecoder().decode([Slot].self, from: data) else { return nil }
        return slots.contains { $0.is_processing == true }
    }

    /// The OpenAI-compatible `/v1/models`, which every server above also answers.
    public static func openAIModels(_ data: Data) -> [String]? {
        struct Reply: Decodable { struct Model: Decodable { var id: String }; var data: [Model] }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.data.map(\.id)
    }
}

import Foundation

/// The icon of the app behind something Islet shows, such as an agent at work. The icon of the app itself when it is
/// installed, asked of the Mac the way the Dock asks for it; else the brand's logo Islet carries; else the symbol, on a
/// tile in the tint.
public struct AppIcon: Equatable, Hashable, Sendable {
    /// The app's identifiers, the first one installed wins.
    public var bundleIdentifiers: [String]
    /// The app's name, to pick the right copy when several share an identifier.
    public var name: String?
    /// The brand's logo, one of the tiles Islet carries, for when the app is not installed.
    public var mark: String?
    public var symbol: String
    public var tint: RGBA

    public init(bundleIdentifiers: [String], name: String? = nil, mark: String? = nil, symbol: String, tint: RGBA) {
        self.bundleIdentifiers = bundleIdentifiers
        self.name = name
        self.mark = mark
        self.symbol = symbol
        self.tint = tint
    }

    /// Islet's own, for an agent no app stands for.
    public static let islet = AppIcon(bundleIdentifiers: [], symbol: "sparkle", tint: .blue)
}

extension AIApp {
    public var icon: AppIcon {
        let symbol = switch role {
        case .assistant: "sparkles"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .models: "cpu"
        }
        return AppIcon(bundleIdentifiers: bundleIdentifiers, name: name, mark: mark, symbol: symbol, tint: agent?.tint ?? AppIcon.islet.tint)
    }
}

extension AICatalog {
    /// The app of this name, whatever its case: agents that report with `islet agent` give a name, not an identifier.
    public static func app(named name: String?) -> AIApp? {
        guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return nil }
        return apps.first { $0.name.lowercased() == name || $0.id == name }
    }
}

extension CodingAgent {
    /// The agent's own logo: Claude's for Claude Code, Gemini's, Cursor's from their apps when they are installed, else
    /// from the logos Islet carries. Codex and GitHub Copilot always show their own logo: the app Codex now lives in is
    /// ChatGPT, and VS Code, where Copilot runs, is not Copilot.
    public var icon: AppIcon {
        switch self {
        case .claude:
            AppIcon(bundleIdentifiers: ["com.anthropic.claudefordesktop"], name: "Claude", mark: "claude", symbol: Self.symbol(for: name), tint: tint)
        case .codex:
            AppIcon(bundleIdentifiers: [], mark: "codex", symbol: Self.symbol(for: name), tint: tint)
        case .gemini:
            AppIcon(bundleIdentifiers: ["com.google.GeminiMacOS"], name: "Gemini", mark: "gemini", symbol: Self.symbol(for: name), tint: tint)
        case .cursor:
            AppIcon(bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], name: "Cursor", mark: "cursor", symbol: Self.symbol(for: name), tint: tint)
        case .copilot:
            AppIcon(bundleIdentifiers: [], mark: "githubcopilot", symbol: Self.symbol(for: name), tint: tint)
        }
    }

    /// The icon of the agent named in a session: a known agent's, an app of the catalog's, else Islet's own.
    public static func icon(for name: String?) -> AppIcon {
        if let agent = named(name) { return agent.icon }
        return AICatalog.app(named: name)?.icon ?? .islet
    }
}

extension ModelServerKind {
    /// The icon of the app that serves models of this kind; llama.cpp and OpenAI-compatible servers have none.
    public var icon: AppIcon {
        let app = AICatalog.apps.first { $0.server == self }
        return AppIcon(bundleIdentifiers: app?.bundleIdentifiers ?? [], name: app?.name, mark: app?.mark, symbol: "cpu",
                       tint: RGBA(red: 0.42, green: 0.45, blue: 0.5))
    }
}

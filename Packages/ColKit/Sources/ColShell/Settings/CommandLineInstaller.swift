import Foundation
import AppKit
import ColCore

/// Puts the `colctl` command on the user's path and connects Claude Code to Col, both without administrator rights.
@MainActor
enum CommandLineInstaller {
    static var bundledTool: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/colctl")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var linkURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/colctl")
    }

    /// What the command's link of this name in ~/.local/bin leads to: the tool inside the app, or, when Homebrew
    /// installed this copy and links the command into it, Homebrew's link. `brew upgrade` quits Col and replaces the app
    /// without opening it again; Homebrew's link follows the new app, so the agents' hooks keep working meanwhile.
    static func linkTarget(_ name: String, tool: URL) -> URL {
        Homebrew.command(name, into: Bundle.main.bundleURL) ?? tool
    }

    /// Links ~/.local/bin/colctl to the tool inside the app. Returns a message for the settings window.
    static func install() -> String {
        guard let tool = bundledTool else { return String(localized: "The command is missing from this build.", bundle: .module) }
        let link = linkURL
        do {
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? link.checkResourceIsReachable()) == true || (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try FileManager.default.removeItem(at: link)
            }
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: linkTarget("colctl", tool: tool))
            return String(localized: "Installed in ~/.local/bin. Try `colctl status`.", bundle: .module)
        } catch {
            return error.localizedDescription
        }
    }

    /// Where each agent keeps its hooks.
    nonisolated static func settingsURL(for agent: CodingAgent, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        switch agent {
        case .claude: home.appendingPathComponent(".claude/settings.json")
        case .codex: home.appendingPathComponent(".codex/hooks.json")
        case .gemini: home.appendingPathComponent(".gemini/settings.json")
        case .cursor: home.appendingPathComponent(".cursor/hooks.json")
        case .copilot: home.appendingPathComponent(".copilot/hooks/col.json")
        }
    }

    /// True when the agent is set up on this Mac: its settings folder exists.
    static func isInstalled(_ agent: CodingAgent) -> Bool {
        FileManager.default.fileExists(atPath: settingsURL(for: agent).deletingLastPathComponent().path)
            || (agent == .cursor && FileManager.default.fileExists(atPath: "/Applications/Cursor.app"))
            || (agent == .copilot && ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"].contains {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            })
    }

    /// True when the agent's settings call `colctl hook`, or `islet hook` as Islet wrote them.
    static func isConnected(_ agent: CodingAgent) -> Bool {
        var urls = [settingsURL(for: agent)]
        if agent == .copilot {
            urls.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot/hooks/islet.json"))
        }
        return urls.contains { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return ["colctl", "islet"].contains { text.contains("\($0)\\\" hook") || text.contains("\($0) hook") }
        }
    }

    static func connect(_ agent: CodingAgent) -> String { runHooks("install", agent) }

    static func disconnect(_ agent: CodingAgent) -> String { runHooks("uninstall", agent) }

    /// Runs `colctl hooks install|uninstall --agent`, which edits the agent's settings and keeps a backup next to them.
    private static func runHooks(_ action: String, _ agent: CodingAgent) -> String {
        guard let tool = bundledTool else { return String(localized: "The command is missing from this build.", bundle: .module) }
        let process = Process()
        process.executableURL = tool
        process.arguments = ["hooks", action, "--agent", agent.rawValue]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return error.localizedDescription
        }
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard action == "install" else {
            return String(localized: "Disconnected. \(agent.name) no longer calls Col.", bundle: .module)
        }
        // Codex runs a new hook only once the user has reviewed it.
        return agent == .codex
            ? String(localized: "Connected. In Codex, run /hooks once and trust Col’s hooks.", bundle: .module)
            : String(localized: "Connected. New \(agent.name) sessions report to Col.", bundle: .module)
    }
}

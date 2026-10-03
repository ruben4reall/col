import Foundation
import Testing

/// `colctl`, built once from CLI/main.swift for these tests, or nil when it does not build. The same folder each run,
/// emptied first, so runs do not pile up copies.
private let colctl: URL? = {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../../CLI/main.swift").standardizedFileURL
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("col-colctl-tests")
    try? FileManager.default.removeItem(at: folder)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let tool = folder.appendingPathComponent("colctl")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swiftc", "-swift-version", "6", "-module-name", "ColCommand", source.path, "-o", tool.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    return process.terminationStatus == 0 ? tool.resolvingSymlinksInPath() : nil
}()

/// A home of its own for the command (CFFIXED_USER_HOME), so that nothing of the user's is read or written.
private struct FakeHome {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var bin: URL { home.appendingPathComponent(".local/bin") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("col-home-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home/.local/bin"), withIntermediateDirectories: true)
    }

    /// Runs the command at `tool` with these arguments, or, with `typed`, as a shell runs it when it is typed: found on
    /// the PATH, under its bare name, from another folder.
    func run(_ tool: URL, _ arguments: [String], typed: Bool = false) throws -> (status: Int32, output: String) {
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let process = Process()
        if typed {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", (["colctl"] + arguments).joined(separator: " ")]
        } else {
            process.executableURL = tool
            process.arguments = arguments
        }
        process.currentDirectoryURL = elsewhere
        process.environment = [
            "CFFIXED_USER_HOME": home.path, "HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin",
            "COL_SOCKET": root.appendingPathComponent("none.sock").path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// A file's permission bits.
private func permissions(of url: URL) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) & 0o777
}

/// The line `colctl hooks status` prints for an agent.
private func status(of agent: String, in output: String) -> String? {
    output.split(separator: "\n").first { $0.hasPrefix(agent) }.map(String.init)
}

struct CommandTests {
    /// Islet 1.2 wrote Copilot's hooks to a file of their own, islet.json, calling ~/.local/bin/islet. Disconnecting
    /// Copilot in Col sets that file aside even though Col's own, col.json, was never written.
    @Test func disconnectingCopilotSetsAsideIsletsHooks() throws {
        let tool = try #require(colctl)
        let fake = try FakeHome()
        defer { fake.remove() }
        let hooks = fake.home.appendingPathComponent(".copilot/hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let command = "\"$HOME/.local/bin/islet\" hook --agent copilot"
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"]
        let settings = ["hooks": Dictionary(uniqueKeysWithValues: events.map { ($0, [["type": "command", "command": command, "timeout": 5]]) })]
        let islet = hooks.appendingPathComponent("islet.json")
        let written = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try written.write(to: islet)
        // The copy Islet kept of that file, readable by the Mac's other accounts.
        let isletCopy = hooks.appendingPathComponent("islet.json.islet-backup")
        try written.write(to: isletCopy)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: isletCopy.path)

        #expect(status(of: "GitHub Copil", in: try fake.run(tool, ["hooks", "status"]).output) == "GitHub Copil connected")

        let uninstall = try fake.run(tool, ["hooks", "uninstall", "--agent", "copilot"])
        #expect(uninstall.status == 0)
        #expect(uninstall.output.contains("Col's hooks removed"))
        #expect(!uninstall.output.contains("nothing to remove"))
        #expect(!FileManager.default.fileExists(atPath: islet.path))
        #expect(try Data(contentsOf: hooks.appendingPathComponent("islet.json.col-backup")) == written)
        #expect(!FileManager.default.fileExists(atPath: hooks.appendingPathComponent("col.json").path))
        #expect(try permissions(of: isletCopy) == 0o600)
        #expect(try Data(contentsOf: isletCopy) == written)
        #expect(status(of: "GitHub Copil", in: try fake.run(tool, ["hooks", "status"]).output) == "GitHub Copil not connected")

        // Nothing is left to remove the second time.
        #expect(try fake.run(tool, ["hooks", "uninstall", "--agent", "copilot"]).output.contains("nothing to remove"))
    }

    /// Connecting Copilot again writes Col's own file and sets Islet's aside, so that VS Code does not call Col twice.
    @Test func connectingCopilotSetsAsideIsletsHooks() throws {
        let tool = try #require(colctl)
        let fake = try FakeHome()
        defer { fake.remove() }
        let hooks = fake.home.appendingPathComponent(".copilot/hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try Data(#"{"hooks":{"Stop":[{"command":"\"$HOME/.local/bin/islet\" hook --agent copilot","timeout":5,"type":"command"}]}}"#.utf8)
            .write(to: hooks.appendingPathComponent("islet.json"))
        let isletCopy = hooks.appendingPathComponent("islet.json.islet-backup")
        try Data("{}".utf8).write(to: isletCopy)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: isletCopy.path)

        let install = try fake.run(tool, ["hooks", "install", "--agent", "copilot"])
        #expect(install.status == 0)
        #expect(install.output.contains("islet.json.col-backup"))
        #expect(try permissions(of: isletCopy) == 0o600)
        #expect(!FileManager.default.fileExists(atPath: hooks.appendingPathComponent("islet.json").path))
        #expect(try String(contentsOf: hooks.appendingPathComponent("col.json"), encoding: .utf8).contains(".local/bin/colctl\\\" hook --agent copilot"))
        #expect(status(of: "GitHub Copil", in: try fake.run(tool, ["hooks", "status"]).output) == "GitHub Copil connected")

        #expect(try fake.run(tool, ["hooks", "uninstall", "--agent", "copilot"]).status == 0)
        #expect(status(of: "GitHub Copil", in: try fake.run(tool, ["hooks", "status"]).output) == "GitHub Copil not connected")
    }

    /// Typed in a terminal, the command is found on the PATH and only knows the name it was typed with: its links still
    /// lead to its own file, never to one of that name in the current folder.
    @Test func typedInATerminalTheCommandLinksToItself() throws {
        let built = try #require(colctl)
        let fake = try FakeHome()
        defer { fake.remove() }
        let tool = fake.root.appendingPathComponent("Applications/Col.app/Contents/Helpers/colctl")
        try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: built, to: tool)
        let colctl = fake.bin.appendingPathComponent("colctl")
        let islet = fake.bin.appendingPathComponent("islet")
        // The link Col made, and Islet's, which led into the app before it took its new name.
        try FileManager.default.createSymbolicLink(at: colctl, withDestinationURL: tool)
        try FileManager.default.createSymbolicLink(atPath: islet.path, withDestinationPath: fake.root.path + "/Applications/Islet.app/Contents/Helpers/islet")

        let install = try fake.run(tool, ["hooks", "install", "--agent", "claude"], typed: true)

        #expect(install.status == 0)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: colctl.path) == tool.path)
        #expect(islet.resolvingSymlinksInPath().path == tool.path)
        #expect(FileManager.default.isExecutableFile(atPath: islet.path))
        #expect(try String(contentsOf: fake.home.appendingPathComponent(".claude/settings.json"), encoding: .utf8).contains(".local/bin/colctl\\\" hook"))
    }
}

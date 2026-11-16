import AppKit
import ColCore

/// Where an agent session runs, as its hook found it: the terminal it is attached to, the processes above the hook,
/// nearest first, and its folder.
struct AgentOrigin: Equatable, Sendable {
    /// The terminal's device, `ttys003`.
    var tty: String?
    var processes: [pid_t]
    var folder: String?

    /// From the query `colctl hook` adds to an event: `tty=ttys003&pids=812,640,1`. Anything malformed is left out.
    init?(query: [String: String], folder: String?) {
        let tty = query["tty"].flatMap { Self.isTerminal($0) ? $0 : nil }
        let processes = (query["pids"] ?? "").split(separator: ",").prefix(32).compactMap { Int32($0) }.filter { $0 > 1 }
        guard tty != nil || !processes.isEmpty else { return nil }
        self.tty = tty
        self.processes = processes
        self.folder = folder.flatMap { $0.hasPrefix("/") ? $0 : nil }
    }

    init(tty: String?, processes: [pid_t], folder: String?) {
        self.tty = tty
        self.processes = processes
        self.folder = folder
    }

    /// A terminal device's name, and nothing that could carry anything else into a script.
    static func isTerminal(_ name: String) -> Bool {
        let digits = name.hasPrefix("ttys") ? name.dropFirst(4) : name.hasPrefix("tty") ? name.dropFirst(3) : ""
        return (1...4).contains(digits.count) && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
    }
}

/// Brings a session's terminal or editor to the front. The app is the first of the hook's ancestors that is a regular
/// app. Terminal and iTerm2 select the tab on the session's terminal, through AppleScript (macOS asks for Automation
/// the first time); VS Code, Cursor, Windsurf, VSCodium and Zed open the session's folder, which brings its window
/// forward; any other app, Ghostty and Warp among them, comes to the front.
@MainActor
enum AgentReveal {
    enum Kind: Equatable {
        case terminal, iTerm, folderEditor, other
    }

    static func kind(of bundleIdentifier: String?) -> Kind {
        switch bundleIdentifier {
        case "com.apple.Terminal": .terminal
        case "com.googlecode.iterm2": .iTerm
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
             "com.vscodium", "dev.zed.Zed", "dev.zed.Zed-Preview":
            .folderEditor
        default: .other
        }
    }

    /// The app that holds the session: the first ancestor macOS knows as an app with windows.
    static func app(for origin: AgentOrigin) -> NSRunningApplication? {
        for pid in origin.processes {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, !app.isTerminated,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                return app
            }
        }
        return nil
    }

    /// False when no app of the session's was found, so the caller can fall back.
    @discardableResult
    static func reveal(_ origin: AgentOrigin) -> Bool {
        guard let app = app(for: origin) else { return false }
        switch kind(of: app.bundleIdentifier) {
        case .terminal, .iTerm:
            guard let tty = origin.tty, let script = selectTab(tty: tty, app: kind(of: app.bundleIdentifier)) else {
                app.activate()
                return true
            }
            // In a process of its own, through osascript: the first time, macOS asks for Automation and the script
            // waits for the answer without holding the island up. When the tab is not found, or Automation is refused,
            // the app still comes forward.
            let pid = app.processIdentifier
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let answer = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                guard answer.trimmingCharacters(in: .whitespacesAndNewlines) != "true" else { return }
                DispatchQueue.main.async { _ = NSRunningApplication(processIdentifier: pid)?.activate() }
            }
            do { try process.run() } catch { app.activate() }
        case .folderEditor:
            if let folder = origin.folder, let bundle = app.bundleURL, FileManager.default.fileExists(atPath: folder) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: bundle, configuration: configuration)
            } else {
                app.activate()
            }
        case .other:
            app.activate()
        }
        return true
    }

    /// The script that selects the tab whose terminal is `tty`, brings its window and the app forward, and answers
    /// whether it found it. Nil for a name that is not a terminal's.
    static func selectTab(tty: String, app: Kind) -> String? {
        guard AgentOrigin.isTerminal(tty) else { return nil }
        let device = "/dev/" + tty
        switch app {
        case .terminal:
            return """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(device)" then
                            if miniaturized of w then set miniaturized of w to false
                            set selected of t to true
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case .iTerm:
            return """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(device)" then
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }
}

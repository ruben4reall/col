import Foundation
import ColCore

/// Runs ColMediaBridge inside /usr/bin/perl and talks to it over two pipes: now playing updates come in on its
/// stdout, commands go out on its stdin. One process for the life of the app, restarted if it dies.
@MainActor
final class MediaBridge {
    var onUpdate: ((NowPlayingUpdate) -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var recentCrashes: [Date] = []
    private var stopping = false

    /// False when the app bundle lacks the bridge, as in `swift run` builds.
    var isAvailable: Bool { Self.resources != nil }

    private static var resources: (script: URL, library: URL)? {
        guard let script = Bundle.main.url(forResource: "media-bridge", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libColMediaBridge.dylib"),
              FileManager.default.fileExists(atPath: library.path)
        else { return nil }
        return (script, library)
    }

    func start() {
        guard process == nil, let resources = Self.resources else { return }
        stopping = false
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [resources.script.path, resources.library.path]
        let output = Pipe()
        let commands = Pipe()
        process.standardOutput = output
        process.standardInput = commands
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // The main queue keeps the chunks in order.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.terminated() } }
        }
        do {
            try process.run()
        } catch {
            return
        }
        self.process = process
        input = commands.fileHandleForWriting
    }

    func stop() {
        stopping = true
        try? input?.close()
        process?.terminate()
    }

    func send(_ command: String) {
        try? input?.write(contentsOf: Data((command + "\n").utf8))
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let update = try? NowPlayingUpdate(from: Data(line)) { onUpdate?(update) }
        }
    }

    /// Restarts a bridge that died, unless it keeps dying: then media stays off rather than spinning.
    private func terminated() {
        process = nil
        input = nil
        buffer.removeAll()
        guard !stopping else { return }
        let now = Date()
        recentCrashes = recentCrashes.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard recentCrashes.count <= 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { self?.start() }
        }
    }
}

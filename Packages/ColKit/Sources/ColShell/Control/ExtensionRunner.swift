import AppKit
import ColCore
import Observation

/// Runs the extensions in ~/Library/Application Support/Col/Extensions, each on its own schedule, and turns what
/// they print into activities. Nothing runs when the folder is empty.
@MainActor
@Observable
final class ExtensionRunner {
    struct Installed: Identifiable, Equatable {
        var id: String { folder }
        var folder: String
        var manifest: ExtensionManifest
        var enabled: Bool
        var lastError: String?
    }

    private(set) var installed: [Installed] = []
    @ObservationIgnored var push: ((ActivityRequest) -> Void)?
    @ObservationIgnored var remove: ((String) -> Void)?
    @ObservationIgnored private var timers: [String: Timer] = [:]
    @ObservationIgnored private var running: Set<String> = []

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Col/Extensions", isDirectory: true)
    }

    private static var disabledKey: String { "disabledExtensions" }

    func reload() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        let disabled = Set(UserDefaults.standard.stringArray(forKey: Self.disabledKey) ?? [])
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        installed = folders.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            let file = url.appendingPathComponent("extension.json")
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data).validated()
            else { return nil }
            return Installed(folder: url.lastPathComponent, manifest: manifest, enabled: !disabled.contains(url.lastPathComponent))
        }
        for item in installed where item.enabled {
            run(item)
            let timer = Timer(timeInterval: item.manifest.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.run(item) }
            }
            timer.tolerance = item.manifest.interval * 0.1
            RunLoop.main.add(timer, forMode: .common)
            timers[item.folder] = timer
        }
    }

    func setEnabled(_ enabled: Bool, folder: String) {
        var disabled = Set(UserDefaults.standard.stringArray(forKey: Self.disabledKey) ?? [])
        if enabled { disabled.remove(folder) } else { disabled.insert(folder) }
        UserDefaults.standard.set(Array(disabled), forKey: Self.disabledKey)
        if !enabled { remove?("api.ext-" + folder) }
        reload()
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.folder)
    }

    /// One run: the command through the shell, in the extension's folder, killed after ten seconds.
    private func run(_ item: Installed) {
        guard !running.contains(item.folder) else { return }
        running.insert(item.folder)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", item.manifest.command]
        process.currentDirectoryURL = Self.folder.appendingPathComponent(item.folder)
        var environment = ProcessInfo.processInfo.environment
        environment["COL_EXTENSION"] = item.folder
        environment["PATH"] = (environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.local/bin"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let folder = item.folder
        process.terminationHandler = { [weak self] finished in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finished(folder, data: data, status: status) }
            }
        }
        do {
            try process.run()
        } catch {
            running.remove(folder)
            note(error.localizedDescription, for: folder)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if process.isRunning { process.terminate() }
        }
    }

    private func finished(_ folder: String, data: Data, status: Int32) {
        running.remove(folder)
        guard status == 0 else {
            note("exit \(status)", for: folder)
            return
        }
        note(nil, for: folder)
        if let request = ExtensionManifest.activity(fromOutput: data, folder: folder) {
            push?(request)
        } else if data.isEmpty || String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remove?("api.ext-" + folder)
        }
    }

    private func note(_ error: String?, for folder: String) {
        guard let index = installed.firstIndex(where: { $0.folder == folder }), installed[index].lastError != error else { return }
        installed[index].lastError = error
    }
}

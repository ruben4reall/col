import Darwin
import Foundation
import Testing
@testable import ColShell

@Suite final class ExtensionProcessTests {
    private let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("col-extension-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The real path, as `pwd -P` prints it: /private/var rather than /var.
        guard let real = realpath(folder.path, nil) else { return folder }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real))
    }()

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func run(_ command: String, environment: [String: String] = ["PATH": "/usr/bin:/bin"], timeout: TimeInterval = 10)
        async throws -> (outcome: ExtensionProcess.Outcome, pid: pid_t) {
        let ended = AsyncStream<ExtensionProcess.Outcome>.makeStream()
        let pid = try ExtensionProcess.run(command, in: folder, environment: environment, timeout: timeout) { outcome in
            ended.continuation.yield(outcome)
            ended.continuation.finish()
        }
        var iterator = ended.stream.makeAsyncIterator()
        let outcome = try #require(await iterator.next())
        return (outcome, pid)
    }

    @Test func runsTheCommandInItsFolderWithItsEnvironment() async throws {
        let (outcome, _) = try await run(
            #"printf '%s|%s|%s' "$COL_EXTENSION" "$(pwd -P)" "$HOME"; echo oops >&2; exit 3"#,
            environment: ["PATH": "/usr/bin:/bin", "COL_EXTENSION": "weather"]
        )
        #expect(String(decoding: outcome.output, as: UTF8.self) == "weather|\(folder.path)|")
        #expect(outcome.status == 3)
    }

    @Test func itAnswersForItselfToMacOS() async throws {
        try #require(ExtensionProcess.disclaims)
        typealias Responsible = @convention(c) (pid_t) -> pid_t
        let symbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid"))
        let responsible = unsafeBitCast(symbol, to: Responsible.self)
        let ended = AsyncStream<ExtensionProcess.Outcome>.makeStream()
        let pid = try ExtensionProcess.run("sleep 1", in: folder, environment: ["PATH": "/usr/bin:/bin"], timeout: 10) { outcome in
            ended.continuation.yield(outcome)
            ended.continuation.finish()
        }
        // Not this process: macOS counts the extension as its own, so it never borrows what this one was allowed.
        #expect(responsible(pid) == pid)
        #expect(responsible(getpid()) != pid)
        var iterator = ended.stream.makeAsyncIterator()
        #expect(await iterator.next()?.status == 0)
    }

    @Test func aRunPastItsTimeStopsWithWhatItStarted() async throws {
        let started = Date()
        // The background sleep keeps the output open: it is stopped too, with the shell, as one group.
        let (outcome, _) = try await run("echo before; sleep 30 & sleep 30", timeout: 0.5)
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(outcome.status == SIGTERM)
        #expect(String(decoding: outcome.output, as: UTF8.self) == "before\n")
    }

    @Test func aRunThatIgnoresTheEndIsKilled() async throws {
        let started = Date()
        let (outcome, _) = try await run("trap '' TERM; sleep 30", timeout: 0.3)
        #expect(Date().timeIntervalSince(started) < ExtensionProcess.grace + 3)
        #expect(outcome.status == SIGKILL)
    }

    @Test func aFolderThatIsGoneFailsToStart() {
        #expect(throws: POSIXError.self) {
            try ExtensionProcess.run("true", in: folder.appendingPathComponent("missing"), environment: [:], timeout: 1) { _ in }
        }
    }
}

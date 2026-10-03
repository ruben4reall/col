import Darwin
import Foundation

/// How an extension's command runs: through the shell, in its folder, as a process that answers for itself to macOS.
///
/// A process Col starts the usual way counts as part of Col for macOS's privacy permissions: it could use the
/// Accessibility, Microphone, Camera, Calendars and Reminders access the user gave Col, and macOS would never ask. An
/// extension is a script that anything running as the user can put in a folder, so it starts the way a terminal starts
/// a command, with Col's responsibility for it disclaimed: macOS asks for what it needs in its own name. Where macOS
/// lacks the call that does this, it starts as before.
enum ExtensionProcess {
    /// What a run printed on stdout, and how it ended: its exit status, or the signal that stopped it.
    struct Outcome: Sendable, Equatable {
        var output: Data
        var status: Int32
    }

    /// The most of a run's output Col reads: an extension prints one small JSON object.
    static let outputLimit = 1 << 20
    /// After its time is up, how long a run has to stop on SIGTERM before SIGKILL.
    static let grace: TimeInterval = 2

    /// Whether the processes started here answer for themselves.
    static var disclaims: Bool { setDisclaim != nil }

    /// Starts `/bin/sh -c command` in `directory` with exactly `environment`, its stdin and stderr on /dev/null. Once
    /// `timeout` is over, it is stopped with everything it started. `finished` is called on a background queue when it
    /// has ended. Returns its process identifier.
    @discardableResult
    static func run(
        _ command: String, in directory: URL, environment: [String: String], timeout: TimeInterval,
        finished: @escaping @Sendable (Outcome) -> Void
    ) throws -> pid_t {
        var ends: [Int32] = [-1, -1]
        guard pipe(&ends) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let (output, input) = (ends[0], ends[1])
        // Nothing else Col starts meanwhile inherits either end.
        _ = fcntl(output, F_SETFD, FD_CLOEXEC)
        _ = fcntl(input, F_SETFD, FD_CLOEXEC)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, input, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // A process group of its own, so the end of its time reaches what it started; the signals of a new process and
        // no descriptor of Col's but the three above.
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var signals = sigset_t()
        sigemptyset(&signals)
        posix_spawnattr_setsigmask(&attributes, &signals)
        sigfillset(&signals)
        posix_spawnattr_setsigdefault(&attributes, &signals)
        if let setDisclaim { _ = setDisclaim(&attributes, 1) }

        var pid: pid_t = 0
        let spawned = withCStrings(["/bin/sh", "-c", command]) { arguments in
            withCStrings(environment.map { "\($0.key)=\($0.value)" }) { variables in
                posix_spawn(&pid, "/bin/sh", &actions, &attributes, arguments, variables)
            }
        }
        close(input)
        guard spawned == 0 else {
            close(output)
            throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .EIO)
        }

        let process = Running(pid: pid)
        let started = DispatchTime.now()
        let queue = DispatchQueue.global(qos: .utility)
        queue.async {
            let printed = collect(output, until: started + timeout + grace)
            close(output)
            finished(Outcome(output: printed, status: process.wait()))
        }
        queue.asyncAfter(deadline: started + timeout) { process.signal(SIGTERM) }
        queue.asyncAfter(deadline: started + timeout + grace) { process.signal(SIGKILL) }
        return pid
    }

    /// Reads what a run prints until it closes its output, prints too much, or `deadline` passes: something it started
    /// in the background that keeps the output open never holds the run up.
    private static func collect(_ file: Int32, until deadline: DispatchTime) -> Data {
        var printed = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        while printed.count < outputLimit {
            let now = DispatchTime.now()
            guard now < deadline else { break }
            let milliseconds = (deadline.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000
            var request = pollfd(fd: file, events: Int16(POLLIN), revents: 0)
            let ready = poll(&request, 1, Int32(clamping: max(milliseconds, 1)))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { break }
            let count = Darwin.read(file, &chunk, chunk.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            printed.append(chunk, count: count)
        }
        return printed
    }

    private static func withCStrings<Result>(_ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> Result) -> Result {
        let pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return body(pointers)
    }

    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    /// The call terminals use to start a command that answers for itself. Not in the SDK's headers, so it is looked
    /// up; nil where macOS does not have it.
    private static var setDisclaim: SetDisclaim? {
        // RTLD_DEFAULT, every image loaded, is ((void *)-2) in <dlfcn.h>: a macro Swift does not import.
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
            .map { unsafeBitCast($0, to: SetDisclaim.self) }
    }

    /// A started process until it is reaped. Signals reach it, and its process group, only before then: until it is
    /// reaped its number cannot be given to another process.
    private final class Running: @unchecked Sendable {
        let pid: pid_t
        private let lock = NSLock()
        private var ended = false

        init(pid: pid_t) {
            self.pid = pid
        }

        func signal(_ signal: Int32) {
            lock.withLock {
                guard !ended else { return }
                kill(-pid, signal)
                kill(pid, signal)
            }
        }

        /// Waits for the process to end, then reaps it: its exit status, or the number of the signal that stopped it.
        func wait() -> Int32 {
            var info = siginfo_t()
            while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}
            lock.withLock { ended = true }
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1, errno == EINTR {}
            return status & 0x7F == 0 ? (status >> 8) & 0xFF : status & 0x7F
        }
    }
}

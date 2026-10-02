import Foundation

struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var body: Data
}

struct HTTPResponse: Sendable {
    var status: Int
    var body: Data

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: data)
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(["error": message], status: status)
    }
}

/// A tiny HTTP server on a Unix domain socket in the user's Application Support folder.
///
/// A socket file rather than a TCP port: only processes running as this user can reach it (the file is 0600), and
/// no web page can, since browsers cannot open Unix sockets. Requests are read on a background queue and routed on
/// the main actor; a route may answer later, which is how a permission request waits for the user.
final class ControlServer: @unchecked Sendable {
    typealias Respond = @Sendable (HTTPResponse) -> Void

    /// Called on the main actor for each request.
    var route: (@MainActor (HTTPRequest, @escaping Respond) -> Void)?

    private let queue = DispatchQueue(label: "ch.rubencatalao.islet.control", attributes: .concurrent)
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    /// `COL_SOCKET` moves it, so a development build can run beside the installed Col without taking its socket.
    static var socketURL: URL {
        if let path = customSocket { return URL(fileURLWithPath: path) }
        return supportFolder.appendingPathComponent("Col", isDirectory: true).appendingPathComponent("col.sock")
    }

    private static var customSocket: String? {
        guard let path = ProcessInfo.processInfo.environment["COL_SOCKET"], !path.isEmpty else { return nil }
        return path
    }

    private static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func start() throws {
        let url = Self.socketURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // A socket that answers belongs to a Col that runs: taking it would cut that one off from its agents.
        guard !Self.isAnswered(at: url) else { throw POSIXError(.EADDRINUSE) }
        guard var address = Self.address(of: url) else { throw POSIXError(.ENAMETOOLONG) }
        unlink(url.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(url.path, 0o600) == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        self.source = source
        if Self.customSocket == nil { Self.answerAsIslet(in: Self.supportFolder) }
    }

    /// Islet listened on Application Support/Islet/islet.sock, and scripts written for it still call there. Its
    /// folder, moved into Col's, became a link to Col's (NameChange); there, Islet's socket is a link to this one. An
    /// Islet folder that is a link elsewhere, of the user's own, is not Col's: nothing is put there.
    static func answerAsIslet(in support: URL) {
        guard NameChange.leads(support.appendingPathComponent("Islet"), to: support.appendingPathComponent("Col")) else { return }
        let socket = support.appendingPathComponent("Col/islet.sock").path
        unlink(socket)
        symlink("col.sock", socket)
    }

    func stop() {
        source?.cancel()
        // Only the Col that made the socket removes it.
        guard listener >= 0 else { return }
        close(listener)
        listener = -1
        unlink(Self.socketURL.path)
    }

    /// Whether a Col listens on the socket now. A file left by a Col that quit refuses the connection.
    static func isAnswered(at url: URL) -> Bool {
        guard var address = address(of: url) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return connected == 0
    }

    private static func address(of url: URL) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(url.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            path.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        return address
    }

    private func accept() {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        queue.async { [weak self] in self?.serve(client) }
    }

    private func serve(_ client: Int32) {
        guard let request = Self.read(client) else {
            Self.write(.error("bad request", status: 400), to: client)
            return
        }
        let respond: Respond = { [queue] response in
            queue.async { Self.write(response, to: client) }
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let route = self?.route else { return respond(.error("unavailable", status: 503)) }
                route(request, respond)
            }
        }
    }

    private static let maximumBody = 1 << 20

    /// One request off the socket; nil for anything that is not a whole, well-formed request, which is answered 400.
    static func read(_ client: Int32) -> HTTPRequest? {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        var headerEnd: Range<Data.Index>?
        while headerEnd == nil {
            let count = recv(client, &chunk, chunk.count, 0)
            guard count > 0 else { return nil }
            data.append(chunk, count: count)
            headerEnd = data.range(of: Data("\r\n\r\n".utf8))
            if data.count > 64 * 1024, headerEnd == nil { return nil }
        }
        guard let headerEnd, let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].lowercased() == "content-length" {
                // A length that is not a count of bytes (negative, or not a number) makes the request a bad one.
                guard let value = Int(pair[1].trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
                length = value
            }
        }
        guard length <= maximumBody else { return nil }
        var body = Data(data[headerEnd.upperBound...])
        while body.count < length {
            let count = recv(client, &chunk, chunk.count, 0)
            guard count > 0 else { return nil }
            body.append(chunk, count: count)
        }
        let target = URLComponents(string: String(parts[1]))
        var query: [String: String] = [:]
        target?.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
        return HTTPRequest(method: String(parts[0]), path: target?.path ?? "/", query: query, body: body.prefix(length))
    }

    private static func write(_ response: HTTPResponse, to client: Int32) {
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 503: "Service Unavailable"][response.status] ?? "Status"
        var message = Data("HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n".utf8)
        message.append(response.body)
        message.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = send(client, buffer.baseAddress! + offset, buffer.count - offset, 0)
                if sent <= 0 { break }
                offset += sent
            }
        }
        close(client)
    }
}

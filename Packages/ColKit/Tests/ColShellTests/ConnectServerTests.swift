import ColCore
import Foundation
import Testing
@testable import ColShell

/// Col Connect's server, listening on this Mac only (loopback, a port the system picks, no Bonjour), reached over TCP
/// as a phone would reach it.
@MainActor
@Suite(.serialized) struct ConnectServerTests {
    static let token = ConnectToken.make()

    private func start() async throws -> (ConnectServer, UInt16) {
        let server = ConnectServer(options: .init(ports: [], loopbackOnly: true, advertises: false))
        server.tokens = { [(device: "phone", token: Self.token)] }
        server.handler = { route, request, device in
            .json(["route": "\(route)", "device": device, "body": String(decoding: request.body, as: UTF8.self)])
        }
        server.pairingPage = { "<html>pair</html>" }
        server.start()
        for _ in 0..<200 where server.port == nil { try await Task.sleep(for: .milliseconds(10)) }
        let port = try #require(server.port)
        #expect(port != 0)
        return (server, port)
    }

    /// Sends these bytes on a new connection and reads the answer until the server closes it.
    private nonisolated static func exchange(_ raw: String, port: UInt16) async throws -> (status: Int, headers: String, body: String) {
        try await Task.detached {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw POSIXError(.EIO) }
            defer { close(fd) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
            let bytes = Array(raw.utf8)
            _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            var response = Data()
            var chunk = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = recv(fd, &chunk, chunk.count, 0)
                if count <= 0 { break }
                response.append(chunk, count: count)
            }
            let text = String(decoding: response, as: UTF8.self)
            let parts = text.components(separatedBy: "\r\n\r\n")
            let status = parts.first?.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
            return (status, parts.first ?? "", parts.dropFirst().joined(separator: "\r\n\r\n"))
        }.value
    }

    private func request(_ method: String, _ path: String, token: String? = token, body: String = "") -> String {
        var head = "\(method) \(path) HTTP/1.1\r\nHost: mac.local\r\nContent-Length: \(body.utf8.count)\r\n"
        if let token { head += "Authorization: Bearer \(token)\r\n" }
        return head + "\r\n" + body
    }

    @Test func aPairedDeviceIsServed() async throws {
        let (server, port) = try await start()
        defer { server.stop() }
        let status = try await Self.exchange(request("GET", "/v1/status"), port: port)
        #expect(status.status == 200)
        #expect(status.body.contains("\"device\":\"phone\""))
        #expect(status.headers.contains("Cache-Control: no-store"))
        let widget = try await Self.exchange(request("PUT", "/v1/widgets/temp", body: #"{"value":21}"#), port: port)
        #expect(widget.status == 200)
        #expect(widget.body.contains("setWidget"))
        #expect(widget.body.contains(#"{\"value\":21}"#))
    }

    @Test func everythingElseNeedsAToken() async throws {
        let (server, port) = try await start()
        defer { server.stop() }
        for raw in [request("GET", "/v1/status", token: nil), request("GET", "/v1/status", token: "guess"),
                    request("POST", "/v1/activities", token: String(Self.token.dropLast()), body: "{}"),
                    "GET /v1/status HTTP/1.1\r\nAuthorization: Basic \(Self.token)\r\n\r\n"] {
            let answer = try await Self.exchange(raw, port: port)
            #expect(answer.status == 401)
            #expect(answer.headers.contains("WWW-Authenticate: Bearer"))
        }
    }

    @Test func agentsCannotBeReachedEvenWithAToken() async throws {
        let (server, port) = try await start()
        defer { server.stop() }
        let event = #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf ~"}}"#
        for path in ["/v1/agents/events", "/v1/agents/events?agent=claude", "/v1/extensions/reload"] {
            let answer = try await Self.exchange(request("POST", path, body: event), port: port)
            #expect(answer.status == 404, "\(path)")
        }
        #expect(try await Self.exchange(request("GET", "/v1/activities"), port: port).status == 405)
    }

    @Test func limitsWhatItReads() async throws {
        let (server, port) = try await start()
        defer { server.stop() }
        // Refused from its head alone, before any of the body is read.
        let big = "POST /v1/activities HTTP/1.1\r\nAuthorization: Bearer \(Self.token)\r\nContent-Length: \(Connect.maximumBody + 1)\r\n\r\n"
        #expect(try await Self.exchange(big, port: port).status == 413)
        let chunked = "POST /v1/activities HTTP/1.1\r\nAuthorization: Bearer \(Self.token)\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n"
        #expect(try await Self.exchange(chunked, port: port).status == 411)
        #expect(try await Self.exchange("NOT HTTP\r\n\r\n", port: port).status == 400)
    }

    @Test func thePairingPageHoldsNoSecret() async throws {
        let (server, port) = try await start()
        defer { server.stop() }
        let page = try await Self.exchange(request("GET", "/connect", token: nil), port: port)
        #expect(page.status == 200)
        #expect(page.headers.contains("Content-Type: text/html"))
        #expect(page.headers.contains("Content-Security-Policy:"))
        #expect(!ConnectPage.html.contains(Self.token))
    }

    @Test func aFloodIsSlowedDown() throws {
        let server = ConnectServer(options: .init(ports: [], loopbackOnly: true, advertises: false))
        server.tokens = { [(device: "phone", token: Self.token)] }
        server.handler = { _, _, _ in .json([:]) }
        let now = Date(timeIntervalSince1970: 0)
        let status = ConnectRequest(method: "GET", path: "/v1/status", query: [:], headers: ["authorization": "Bearer \(Self.token)"], body: Data())
        let statuses = (0..<70).map { _ in server.answer(status, from: "192.168.1.30", now: now).status }
        #expect(statuses.prefix(60).allSatisfy { $0 == 200 })
        #expect(statuses.suffix(10).allSatisfy { $0 == 429 })
        // Another device of the network is not held up by the first.
        #expect(server.answer(status, from: "192.168.1.31", now: now).status == 200)
        // A second later, the first is served again.
        #expect(server.answer(status, from: "192.168.1.30", now: now.addingTimeInterval(1)).status == 200)
    }

    @Test func guessingTokensLocksTheGuesserOut() throws {
        let server = ConnectServer(options: .init(ports: [], loopbackOnly: true, advertises: false))
        server.tokens = { [(device: "phone", token: Self.token)] }
        server.handler = { _, _, _ in .json([:]) }
        let now = Date(timeIntervalSince1970: 0)
        func status(_ token: String, from address: String, at time: Date) -> Int {
            server.answer(ConnectRequest(method: "GET", path: "/v1/status", query: [:], headers: ["authorization": "Bearer \(token)"], body: Data()),
                          from: address, now: time).status
        }
        let guesses = (0..<10).map { status("guess\($0)", from: "10.0.0.66", at: now) }
        #expect(guesses.allSatisfy { $0 == 401 })
        // Even the right token is refused from there for a while.
        #expect(status(Self.token, from: "10.0.0.66", at: now) == 429)
        #expect(status(Self.token, from: "10.0.0.7", at: now) == 200)
        #expect(status(Self.token, from: "10.0.0.66", at: now.addingTimeInterval(31)) == 200)
    }
}

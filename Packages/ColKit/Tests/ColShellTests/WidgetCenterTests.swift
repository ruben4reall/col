import ColCore
import Foundation
import Testing
@testable import ColShell

/// A small HTTP server on this Mac only, answering each request with what `answer` gives for its path, and keeping
/// every request's head to look at.
private final class LoopbackServer: @unchecked Sendable {
    let port: UInt16
    private let fd: Int32
    private let lock = NSLock()
    private var heads: [String] = []

    init(answer: @escaping @Sendable (_ path: String, _ port: UInt16) -> String) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        let port = UInt16(bigEndian: address.sin_port)
        self.fd = fd
        self.port = port
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                var chunk = [UInt8](repeating: 0, count: 8192)
                var data = Data()
                while !data.contains("\r\n\r\n".utf8) {
                    let count = recv(client, &chunk, chunk.count, 0)
                    if count <= 0 { break }
                    data.append(chunk, count: count)
                }
                let head = String(decoding: data, as: UTF8.self)
                self?.lock.withLock { self?.heads.append(head) }
                let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let bytes = Array(answer(path, port).utf8)
                _ = bytes.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
                close(client)
            }
        }
    }

    var requests: [String] { lock.withLock { heads } }

    func stop() { close(fd) }

    static func response(_ status: String, body: String = "", extra: String = "") -> String {
        "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\(extra)\r\n\(body)"
    }
}

@MainActor
@Suite(.serialized) struct WidgetCenterTests {
    @Test func aReadNeverTakesItsHeadersToAnotherHost() async throws {
        // 127.0.0.1 sends the read to localhost: the same server, another host for the browser's rules and Col's.
        let server = try LoopbackServer { path, port in
            path == "/start"
                ? LoopbackServer.response("302 Found", extra: "Location: http://localhost:\(port)/landed\r\n")
                : LoopbackServer.response("200 OK", body: #"{"value":1}"#)
        }
        defer { server.stop() }
        let definition = APIWidget(id: "url-test", name: "Test", url: "http://127.0.0.1:\(server.port)/start", headers: ["X-Api-Key"])
        await #expect(throws: WidgetCenter.ReadError.status(302)) {
            try await WidgetCenter.read(definition, session: WidgetCenter.makeSession(redirects: .sameOrigin), headers: ["X-Api-Key": "SECRET"])
        }
        #expect(server.requests.count == 1)
        #expect(server.requests.allSatisfy { !$0.contains("/landed") })
    }

    @Test func aReadFollowsARedirectWithinItsOwnAddress() async throws {
        let server = try LoopbackServer { path, port in
            path == "/start"
                ? LoopbackServer.response("302 Found", extra: "Location: http://127.0.0.1:\(port)/now\r\n")
                : LoopbackServer.response("200 OK", body: #"{"value":21}"#)
        }
        defer { server.stop() }
        let definition = APIWidget(id: "url-test", name: "Test", url: "http://127.0.0.1:\(server.port)/start", headers: ["X-Api-Key"])
        let read = try await WidgetCenter.read(definition, session: WidgetCenter.makeSession(redirects: .sameOrigin), headers: ["X-Api-Key": "SECRET"])
        #expect(read.widget.value == "21")
        #expect(server.requests.last?.contains("X-Api-Key: SECRET") == true)
    }

    @Test func aReadStopsPastTheLimit() async throws {
        let big = "{\"value\":\"" + String(repeating: "x", count: WidgetCenter.maximumAnswer) + "\"}"
        // Without a length, so the size is only known while reading.
        let server = try LoopbackServer { _, _ in "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n" + big }
        defer { server.stop() }
        await #expect(throws: WidgetCenter.ReadError.tooLarge) {
            try await WidgetCenter.fetch("http://127.0.0.1:\(server.port)/big", headers: [:], session: WidgetCenter.makeSession(redirects: .sameOrigin))
        }
    }

    @Test func redirectsStayWithinTheirOrigin() {
        let origin = URL(string: "https://api.example.com/now")
        #expect(RedirectPolicy.sameOrigin(origin, URL(string: "https://api.example.com/v2/now")))
        #expect(RedirectPolicy.sameOrigin(origin, URL(string: "https://API.example.com:443/now")))
        #expect(!RedirectPolicy.sameOrigin(origin, URL(string: "http://api.example.com/now")))
        #expect(!RedirectPolicy.sameOrigin(origin, URL(string: "https://api.example.com:8443/now")))
        #expect(!RedirectPolicy.sameOrigin(origin, URL(string: "https://evil.example/now")))
        #expect(!RedirectPolicy.sameOrigin(origin, nil))
    }

    @Test func theWidgetsPlaceHoldsAFewDozenAtMost() throws {
        let center = WidgetCenter(file: nil, definitions: [])
        for index in 0..<WidgetCenter.maximumPushed {
            #expect(center.set(try WidgetRequest(id: "w\(index)", value: "\(index)").validated()))
        }
        // A new one is refused; an existing one is still updated.
        #expect(!center.set(try WidgetRequest(id: "one-more").validated()))
        #expect(center.set(try WidgetRequest(id: "w3", value: "updated").validated()))
        #expect(center.pushed.count == WidgetCenter.maximumPushed)
        #expect(center.pushed[3].widget.value == "updated")
        // Through the API, the sender is told why.
        let api = ControlAPI(custom: CustomActivities(), agents: AgentCenter(), widgets: center, post: { _ in }, remove: { _ in })
        let (status, body) = api.setWidget("one-more", body: Data(#"{"value":1}"#.utf8))
        #expect(status == 409)
        #expect((body["error"] as? String)?.contains("at most") == true)
        let response = api.connect(.setWidget("one-more"), ConnectRequest(method: "PUT", path: "/v1/widgets/one-more", body: Data("{}".utf8)))
        #expect(response.status == 409)
    }

    @Test func pushedActivitiesAreBoundedToo() throws {
        let custom = CustomActivities()
        let api = ControlAPI(custom: custom, agents: AgentCenter(), widgets: WidgetCenter(file: nil, definitions: []), post: { _ in }, remove: { _ in })
        for index in 0..<CustomActivities.maximum {
            #expect(api.push(try ActivityRequest(id: "a\(index)").validated()))
        }
        #expect(!api.push(try ActivityRequest(id: "one-more").validated()))
        #expect(api.push(try ActivityRequest(id: "a0", title: "Again").validated()))
        let response = api.connect(.pushActivity, ConnectRequest(method: "POST", path: "/v1/activities", body: Data(#"{"id":"one-more"}"#.utf8)))
        #expect(response.status == 409)
        // One that has ended makes room.
        let now = Date()
        _ = custom.finish("a1", text: nil, now: now.addingTimeInterval(-10))
        #expect(api.push(try ActivityRequest(id: "one-more").validated()))
    }

    @Test func aButtonIsApprovedForItsOwnWidget() {
        let center = WidgetCenter(file: nil, definitions: [])
        let button = WidgetButton(title: "Heat", url: "https://ha.example/api/webhook/heat")
        let key = button.confirmationKey(widget: "living-room")
        let saved = Preferences.confirmedWidgetCalls
        defer { Preferences.confirmedWidgetCalls = saved }
        Preferences.confirmedWidgetCalls = [key]
        // Approved for the living room: another widget with the same address asks first.
        center.press(button, of: "garage")
        #expect(center.confirming?.widget == "garage")
        center.cancelConfirmation()
        #expect(center.confirming == nil)
    }
}

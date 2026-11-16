import Foundation
import Testing
@testable import ColCore

@Suite struct ConnectTests {
    @Test func tokensAreLongAndUnguessable() {
        let tokens = (0..<50).map { _ in ConnectToken.make() }
        #expect(Set(tokens).count == 50)
        #expect(tokens.allSatisfy { $0.count == 43 })
        #expect(tokens.allSatisfy { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } })
    }

    @Test func tokensMatchOnlyWhole() {
        let token = ConnectToken.make()
        #expect(ConnectToken.matches(token, token))
        #expect(!ConnectToken.matches(token, String(token.dropLast())))
        #expect(!ConnectToken.matches(token, token + "x"))
        #expect(!ConnectToken.matches(token, ""))
        #expect(!ConnectToken.matches("", ""))
        // A guess 256 characters longer must not wrap around to the same length.
        #expect(!ConnectToken.matches(token, token + String(repeating: "a", count: 256)))
    }

    @Test func onlyABearerTokenAuthenticates() {
        let tokens = [(device: "phone", token: "aaa"), (device: "server", token: "bbb")]
        #expect(ConnectAuth.device(for: "Bearer bbb", tokens: tokens) == "server")
        #expect(ConnectAuth.device(for: "bearer   aaa ", tokens: tokens) == "phone")
        #expect(ConnectAuth.device(for: nil, tokens: tokens) == nil)
        #expect(ConnectAuth.device(for: "Bearer ", tokens: tokens) == nil)
        #expect(ConnectAuth.device(for: "Basic aaa", tokens: tokens) == nil)
        #expect(ConnectAuth.device(for: "aaa", tokens: tokens) == nil)
        #expect(ConnectAuth.device(for: "Bearer ccc", tokens: tokens) == nil)
        #expect(ConnectAuth.device(for: "Bearer aaa", tokens: []) == nil)
        #expect(ConnectAuth.bearer("Bearer " + String(repeating: "x", count: 300)) == nil)
    }

    @Test func routesMirrorTheLocalAPI() {
        #expect(ConnectRoute.resolve(method: "GET", path: "/v1/status") == .success(.status))
        #expect(ConnectRoute.resolve(method: "POST", path: "/v1/activities") == .success(.pushActivity))
        #expect(ConnectRoute.resolve(method: "POST", path: "/v1/activities/build/done") == .success(.finishActivity("build")))
        #expect(ConnectRoute.resolve(method: "DELETE", path: "/v1/activities/build") == .success(.removeActivity("build")))
        #expect(ConnectRoute.resolve(method: "PUT", path: "/v1/widgets/temp") == .success(.setWidget("temp")))
        #expect(ConnectRoute.resolve(method: "DELETE", path: "/v1/widgets/temp") == .success(.removeWidget("temp")))
        #expect(ConnectRoute.resolve(method: "GET", path: "/v1/activities/build") == .failure(.methodNotAllowed))
    }

    @Test func agentsAreNeverReachable() {
        // Allow and Deny stay on the Mac: no route reaches an agent, whatever the method.
        for method in ["GET", "POST", "PUT", "DELETE"] {
            for path in ["/v1/agents/events", "/v1/agents/events?agent=claude", "/v1/agents", "/v1/activities/x/y/z", "/", "/connect/x",
                         "/v2/status", "/v1/extensions/reload"] {
                let route = ConnectRoute.resolve(method: method, path: URLComponents(string: path)!.path)
                #expect(route == .failure(.notFound), "\(method) \(path)")
            }
        }
        // Nor does listing what runs on the Mac.
        #expect(ConnectRoute.resolve(method: "GET", path: "/v1/activities") == .failure(.methodNotAllowed))
    }

    @Test func readsAWholeRequest() throws {
        let raw = "PUT /v1/widgets/temp?x=1 HTTP/1.1\r\nHost: mac.local\r\nAuthorization: Bearer abc\r\nContent-Length: 2\r\n\r\n{}"
        guard case .complete(let request) = ConnectRequest.parse(Data(raw.utf8)) else { Issue.record("not complete"); return }
        #expect(request.method == "PUT")
        #expect(request.path == "/v1/widgets/temp")
        #expect(request.query == ["x": "1"])
        #expect(request.headers["authorization"] == "Bearer abc")
        #expect(request.body == Data("{}".utf8))
        // Arriving in pieces.
        #expect(ConnectRequest.parse(Data("PUT /v1/widgets/temp HTTP/1.1\r\nContent-Length: 5\r\n\r\n{}".utf8)) == .incomplete)
        #expect(ConnectRequest.parse(Data("GET /v1/status HTTP/1.1\r\n".utf8)) == .incomplete)
    }

    @Test func refusesWhatIsTooBigOrMalformed() {
        let big = "POST /v1/activities HTTP/1.1\r\nContent-Length: \(Connect.maximumBody + 1)\r\n\r\n"
        #expect(ConnectRequest.parse(Data(big.utf8)) == .failed(413))
        let longHead = "GET /v1/status HTTP/1.1\r\nX-Pad: " + String(repeating: "a", count: Connect.maximumHead) + "\r\n\r\n"
        #expect(ConnectRequest.parse(Data(longHead.utf8)) == .failed(431))
        #expect(ConnectRequest.parse(Data(String(repeating: "a", count: Connect.maximumHead + 1).utf8)) == .failed(431))
        #expect(ConnectRequest.parse(Data("POST /v1/activities HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)) == .failed(411))
        #expect(ConnectRequest.parse(Data("POST /v1/activities HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)) == .failed(400))
        #expect(ConnectRequest.parse(Data("POST /v1/activities HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab".utf8)) == .failed(400))
        #expect(ConnectRequest.parse(Data("GET\r\n\r\n".utf8)) == .failed(400))
        #expect(ConnectRequest.parse(Data("get /v1/status HTTP/1.1\r\n\r\n".utf8)) == .failed(400))
        #expect(ConnectRequest.parse(Data("GET v1/status HTTP/1.1\r\n\r\n".utf8)) == .failed(400))
        #expect(ConnectRequest.parse(Data("GET /v1/status SPDY/3\r\n\r\n".utf8)) == .failed(400))
        #expect(ConnectRequest.parse(Data("GET /v1/status HTTP/1.1\r\nno colon\r\n\r\n".utf8)) == .failed(400))
    }

    @Test func aFloodRunsDryAndRefills() {
        var limiter = RateLimiter(capacity: 5, perSecond: 1)
        let start = Date(timeIntervalSince1970: 0)
        let burst = (0..<6).map { _ in limiter.allow("10.0.0.2", now: start) }
        #expect(burst == [true, true, true, true, true, false])
        #expect(limiter.isLimited("10.0.0.2", now: start))
        // Another address has its own bucket.
        let other = limiter.allow("10.0.0.3", now: start)
        #expect(other)
        // Two seconds later, two more.
        let later = (0..<3).map { _ in limiter.allow("10.0.0.2", now: start.addingTimeInterval(2)) }
        #expect(later == [true, true, false])
    }

    @Test func remembersABoundedNumberOfAddresses() {
        var limiter = RateLimiter(capacity: 2, perSecond: 0.001, memory: 4)
        let now = Date(timeIntervalSince1970: 0)
        _ = limiter.allow("busy", now: now)
        _ = limiter.allow("busy", now: now)
        for index in 0..<10 { _ = limiter.allow("visitor\(index)", now: now) }
        // The address that ran dry is the one worth remembering.
        #expect(limiter.isLimited("busy", now: now))
    }

    @Test func onlyTheLocalNetworkIsLocal() {
        #expect(LANAddress.isLocal([192, 168, 1, 20]))
        #expect(LANAddress.isLocal([10, 0, 0, 1]))
        #expect(LANAddress.isLocal([172, 16, 0, 1]))
        #expect(LANAddress.isLocal([172, 31, 255, 1]))
        #expect(LANAddress.isLocal([127, 0, 0, 1]))
        #expect(LANAddress.isLocal([169, 254, 3, 4]))
        #expect(!LANAddress.isLocal([172, 32, 0, 1]))
        #expect(!LANAddress.isLocal([8, 8, 8, 8]))
        #expect(!LANAddress.isLocal([100, 64, 0, 1]))
        var loopback = [UInt8](repeating: 0, count: 16)
        loopback[15] = 1
        #expect(LANAddress.isLocal(loopback))
        #expect(LANAddress.isLocal([0xFE, 0x80] + [UInt8](repeating: 0, count: 13) + [1]))
        #expect(LANAddress.isLocal([0xFD, 0x12] + [UInt8](repeating: 0, count: 14)))
        #expect(LANAddress.isLocal([UInt8](repeating: 0, count: 10) + [0xFF, 0xFF, 192, 168, 0, 9]))
        #expect(!LANAddress.isLocal([UInt8](repeating: 0, count: 10) + [0xFF, 0xFF, 1, 1, 1, 1]))
        #expect(!LANAddress.isLocal([0x20, 0x01, 0x0d, 0xb8] + [UInt8](repeating: 0, count: 12)))
        #expect(!LANAddress.isLocal([1, 2, 3]))
    }
}

import Foundation
import Testing
@testable import ColShell

@Suite struct ControlServerTests {
    /// What the server reads from a client that wrote `raw` and nothing more.
    private func read(_ raw: String) -> HTTPRequest? {
        var ends: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &ends) == 0 else { return nil }
        defer { close(ends[0]) }
        let bytes = Array(raw.utf8)
        _ = bytes.withUnsafeBytes { send(ends[1], $0.baseAddress, $0.count, 0) }
        // The client is done: a body that never comes ends the read instead of waiting for it.
        close(ends[1])
        return ControlServer.read(ends[0])
    }

    @Test func readsARequestAndItsBody() throws {
        let request = try #require(read("POST /v1/activities?x=1 HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}"))
        #expect(request.method == "POST")
        #expect(request.path == "/v1/activities")
        #expect(request.query == ["x": "1"])
        #expect(request.body == Data("{}".utf8))
    }

    @Test func aNegativeLengthIsABadRequest() {
        #expect(read("POST /v1/activities HTTP/1.1\r\nContent-Length: -5\r\n\r\n") == nil)
        #expect(read("POST /v1/activities HTTP/1.1\r\ncontent-length:-1\r\n\r\nabc") == nil)
    }

    @Test func aLengthThatIsNotANumberIsABadRequest() {
        #expect(read("POST /v1/activities HTTP/1.1\r\nContent-Length: five\r\n\r\n") == nil)
        #expect(read("POST /v1/activities HTTP/1.1\r\nContent-Length: 99999999999999999999\r\n\r\n") == nil)
    }

    @Test func noLengthMeansNoBody() throws {
        let request = try #require(read("GET /v1/status HTTP/1.1\r\n\r\n"))
        #expect(request.body.isEmpty)
    }
}

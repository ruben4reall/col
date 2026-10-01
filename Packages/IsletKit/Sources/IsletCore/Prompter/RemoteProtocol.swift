import Foundation

/// What the phone remote can ask for.
public enum RemoteCommand: String, CaseIterable, Codable, Sendable {
    case toggle, faster, slower, back, forward, restart
}

/// What the phone remote shows, sent as JSON each time it changes.
public struct RemoteState: Codable, Equatable, Sendable {
    /// The open script, or the one selected in the library when nothing is open.
    public var title: String
    /// A take is open on the Mac, rolling or paused.
    public var isActive: Bool
    public var isRolling: Bool
    /// From 0 to 1.
    public var progress: Double
    public var wordsPerMinute: Double
    /// The line under the camera.
    public var line: String
    /// Seconds left at the current pace.
    public var remaining: TimeInterval

    public init(title: String, isActive: Bool = true, isRolling: Bool, progress: Double, wordsPerMinute: Double, line: String, remaining: TimeInterval) {
        self.title = title
        self.isActive = isActive
        self.isRolling = isRolling
        self.progress = progress
        self.wordsPerMinute = wordsPerMinute
        self.line = line
        self.remaining = remaining
    }

    /// Nothing open on the Mac: the phone shows the selected script and what its play button does.
    public static func idle(title: String = "") -> RemoteState {
        RemoteState(title: title, isActive: false, isRolling: false, progress: 0, wordsPerMinute: 0, line: "", remaining: 0)
    }
}

/// The pairing secret in the remote's address: without it the server answers nothing.
public enum RemoteToken {
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<12).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
    }

    /// Compares in constant time, so the answer's timing says nothing about how much of a guess was right.
    public static func matches(_ expected: String, _ given: String) -> Bool {
        let a = Array(expected.utf8), b = Array(given.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }
}

/// The part of an HTTP/1.1 request the remote needs: method, path, query and headers.
public struct HTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    /// Header names in lower case.
    public let headers: [String: String]

    /// Nil until the whole head has arrived (it ends with an empty line), or when it is not HTTP.
    public init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), let end = text.range(of: "\r\n\r\n") else { return nil }
        let lines = text[..<end.lowerBound].components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/"), let components = URLComponents(string: String(parts[1])) else { return nil }
        method = String(parts[0])
        path = components.path.isEmpty ? "/" : components.path
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        self.query = query
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        self.headers = headers
    }
}

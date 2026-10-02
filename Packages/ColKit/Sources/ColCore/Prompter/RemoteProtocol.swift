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

/// The phone remote's connections still on their way to a request, and the slots they hold. A slot is never held
/// against a newcomer: a phone's request follows its connection within moments, so when every slot is taken the
/// connection waiting longest goes, from the address holding the most, and one address never holds more than a few.
/// Connections opened and left silent on purpose, from one address or many, can then no longer keep the phone out.
public struct PendingConnections: Sendable {
    public struct Entry: Equatable, Sendable {
        public let id: UInt64
        public let host: String
    }

    /// Oldest first.
    public private(set) var entries: [Entry] = []
    /// Slots for every connection, those still waiting and those already let in.
    public let limit: Int
    /// Slots one address may hold while its requests are on their way.
    public let perHost: Int

    public init(limit: Int, perHost: Int) {
        self.limit = limit
        self.perHost = perHost
    }

    public var count: Int { entries.count }

    public func contains(_ id: UInt64) -> Bool {
        entries.contains { $0.id == id }
    }

    /// Lets a connection from `host` wait for its request, beside `others` connections already let in: returns the
    /// connections that go to make room for it, or nil when there is none to make, every slot being held by a phone.
    public mutating func admit(_ id: UInt64, from host: String, besides others: Int) -> [UInt64]? {
        var leaving: [UInt64] = []
        // An address past its share makes room from its own connections, never from anyone else's.
        let own = entries.filter { $0.host == host }
        if own.count >= perHost, let oldest = own.first {
            remove(oldest.id)
            leaving.append(oldest.id)
        }
        while entries.count + others >= limit {
            guard let oldest = oldestOfTheBusiest else { return nil }
            remove(oldest)
            leaving.append(oldest)
        }
        entries.append(Entry(id: id, host: host))
        return leaving
    }

    /// A connection stops waiting: its request came, or it closed or ran out of time. False when it had already gone.
    @discardableResult
    public mutating func remove(_ id: UInt64) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: index)
        return true
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    /// The connection waiting longest among those of the address holding the most.
    private var oldestOfTheBusiest: UInt64? {
        var counts: [String: Int] = [:]
        for entry in entries { counts[entry.host, default: 0] += 1 }
        guard let most = counts.values.max() else { return nil }
        return entries.first { counts[$0.host] == most }?.id
    }
}

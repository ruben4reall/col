import Foundation

/// The rules of Col Connect, the server that lets the devices of the local network push activities and widgets into
/// the island: who may ask, what they may ask for, and how much. Off until the user turns it on; every request carries
/// the token of a device the user paired; agents' permission requests are never reachable from it.
public enum Connect {
    /// The first port Col tries; the prompter's phone remote takes 7575 to 7579.
    public static let preferredPorts: [UInt16] = [7580, 7581, 7582, 7583, 7584]
    /// The Bonjour type Col advertises while Connect is on.
    public static let serviceType = "_col._tcp"
    /// A request's line and headers.
    public static let maximumHead = 8 * 1024
    /// A request's body: an activity or a widget is a few hundred bytes.
    public static let maximumBody = 64 * 1024
    /// Seconds a connection has to send its whole request.
    public static let requestTimeout: TimeInterval = 5
    /// Connections at once, and those one address may hold while their requests are on their way.
    public static let maximumConnections = 16
    public static let maximumPendingPerAddress = 4
}

/// The secret a paired device sends with each request.
public enum ConnectToken {
    /// 32 random bytes, in base64url without padding: 43 characters that survive any URL, header or text field.
    public static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Compares in constant time for tokens of the same length, so the answer's timing says nothing about how much of
    /// a guess was right. Tokens all have the same length, so a length that differs says nothing either.
    public static func matches(_ expected: String, _ given: String) -> Bool {
        let a = Array(expected.utf8), b = Array(given.utf8)
        var difference = a.count ^ b.count
        for index in 0..<a.count { difference |= Int(a[index] ^ (index < b.count ? b[index] : 0)) }
        return difference == 0 && !a.isEmpty
    }
}

public enum ConnectAuth {
    /// The token of an `Authorization: Bearer <token>` header; nil without one.
    public static func bearer(_ header: String?) -> String? {
        guard let header = header?.trimmingCharacters(in: .whitespaces) else { return nil }
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        let token = parts[1].trimmingCharacters(in: .whitespaces)
        return token.isEmpty || token.count > 256 ? nil : token
    }

    /// The device whose token the header carries. Every token is compared, whichever matches, so the time taken says
    /// nothing about which device, or how many, there are.
    public static func device(for header: String?, tokens: [(device: String, token: String)]) -> String? {
        guard let given = bearer(header) else { return nil }
        var found: String?
        for entry in tokens where ConnectToken.matches(entry.token, given) {
            if found == nil { found = entry.device }
        }
        return found
    }
}

/// What a paired device may ask for: the routes of the local API that push into the island, and nothing else. No
/// agent's permission request, no list of what runs on the Mac.
public enum ConnectRoute: Equatable, Sendable {
    case status
    case pushActivity
    case finishActivity(String)
    case removeActivity(String)
    case setWidget(String)
    case removeWidget(String)

    public enum Failure: Error, Equatable, Sendable {
        case notFound
        case methodNotAllowed
    }

    public static func resolve(method: String, path: String) -> Result<ConnectRoute, Failure> {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.first == "v1" else { return .failure(.notFound) }
        let route = Array(parts.dropFirst())
        let method = method.uppercased()
        switch route.count {
        case 1 where route[0] == "status":
            return method == "GET" ? .success(.status) : .failure(.methodNotAllowed)
        case 1 where route[0] == "activities":
            return method == "POST" ? .success(.pushActivity) : .failure(.methodNotAllowed)
        case 2 where route[0] == "activities" && !route[1].isEmpty:
            return method == "DELETE" ? .success(.removeActivity(route[1])) : .failure(.methodNotAllowed)
        case 3 where route[0] == "activities" && route[2] == "done" && !route[1].isEmpty:
            return method == "POST" ? .success(.finishActivity(route[1])) : .failure(.methodNotAllowed)
        case 2 where route[0] == "widgets" && !route[1].isEmpty:
            switch method {
            case "PUT", "POST": return .success(.setWidget(route[1]))
            case "DELETE": return .success(.removeWidget(route[1]))
            default: return .failure(.methodNotAllowed)
            }
        default:
            return .failure(.notFound)
        }
    }
}

/// A whole request as Connect reads it: its line, headers and body, within limits.
public struct ConnectRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    /// Header names in lower case.
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    public enum Parse: Equatable, Sendable {
        /// More bytes are needed.
        case incomplete
        case complete(ConnectRequest)
        /// The request cannot be served: the HTTP status to answer before closing.
        case failed(Int)
    }

    /// Reads what has arrived so far. Nothing is kept past the limits: a head longer than `maximumHead` is 431, a
    /// body longer than `maximumBody` 413, a chunked body 411 (every client Col expects sends a length).
    public static func parse(_ data: Data, maximumHead: Int = Connect.maximumHead, maximumBody: Int = Connect.maximumBody) -> Parse {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maximumHead ? .failed(431) : .incomplete
        }
        guard end.lowerBound - data.startIndex <= maximumHead else { return .failed(431) }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .failed(400) }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isLetter && $0.isUppercase }), parts[1].hasPrefix("/"),
              let components = URLComponents(string: String(parts[1]))
        else { return .failed(400) }
        var headers: [String: String] = [:]
        var length: Int?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .failed(400) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .failed(400) }
            if name == "content-length" {
                guard let number = Int(value), number >= 0, length == nil || length == number else { return .failed(400) }
                length = number
            }
            if name == "transfer-encoding" { return .failed(411) }
            headers[name] = value
        }
        let size = length ?? 0
        guard size <= maximumBody else { return .failed(413) }
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= size else { return .incomplete }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return .complete(ConnectRequest(
            method: String(parts[0]), path: components.path.isEmpty ? "/" : components.path, query: query, headers: headers,
            body: Data(data[bodyStart..<(bodyStart + size)])
        ))
    }
}

/// How often each address may ask: a bucket of `capacity` requests that refills at `perSecond`. A burst of pushes
/// from a build goes through; a flood does not.
public struct RateLimiter: Sendable {
    public let capacity: Double
    public let perSecond: Double
    private var buckets: [String: (tokens: Double, at: Date)] = [:]
    /// Addresses remembered at most: the fullest are forgotten first, as a full bucket says nothing.
    public let memory: Int

    public init(capacity: Double, perSecond: Double, memory: Int = 256) {
        self.capacity = capacity
        self.perSecond = perSecond
        self.memory = memory
    }

    private func level(_ key: String, now: Date) -> Double {
        guard let bucket = buckets[key] else { return capacity }
        return min(capacity, bucket.tokens + max(0, now.timeIntervalSince(bucket.at)) * perSecond)
    }

    /// Takes one request from the address's bucket: false when it is empty.
    public mutating func allow(_ key: String, now: Date) -> Bool {
        let tokens = level(key, now: now)
        guard tokens >= 1 else {
            buckets[key] = (tokens, now)
            return false
        }
        buckets[key] = (tokens - 1, now)
        if buckets.count > memory { forgetFullest(now: now) }
        return true
    }

    /// Whether the address has run out, without taking anything.
    public func isLimited(_ key: String, now: Date) -> Bool {
        level(key, now: now) < 1
    }

    private mutating func forgetFullest(now: Date) {
        let fullest = buckets.keys.sorted { level($0, now: now) > level($1, now: now) }.prefix(buckets.count - memory)
        for key in fullest { buckets[key] = nil }
    }
}

/// Which addresses are on the local network: loopback, private and link-local ranges, IPv4 and IPv6.
public enum LANAddress {
    /// `bytes` is an address as the network gives it: 4 bytes for IPv4, 16 for IPv6.
    public static func isLocal(_ bytes: [UInt8]) -> Bool {
        switch bytes.count {
        case 4:
            return isLocalIPv4(bytes)
        case 16:
            if bytes[0..<15].allSatisfy({ $0 == 0 }), bytes[15] == 1 { return true } // ::1
            if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true } // fe80::/10
            if bytes[0] & 0xFE == 0xFC { return true } // fc00::/7
            if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
                return isLocalIPv4(Array(bytes[12..<16]))
            }
            return false
        default:
            return false
        }
    }

    /// Whether `address` is on the same link as an address of the Mac's, given that address's netmask: a phone of the
    /// home network reaching the Mac by its `.local` name often comes from a global IPv6 address, in the same prefix as
    /// the Mac's own. A netmask longer than 64 bits, as some interfaces give their temporary addresses, counts as 64.
    public static func isOnLink(_ address: [UInt8], interface: [UInt8], netmask: [UInt8]) -> Bool {
        guard address.count == interface.count, netmask.count == interface.count, !address.isEmpty else { return false }
        var mask = netmask
        if mask.count == 16 {
            let bits = mask.reduce(0) { $0 + $1.nonzeroBitCount }
            // A /0 says nothing about a link; past /64 is a single address, not a network.
            guard bits >= 8 else { return false }
            if bits > 64 { mask = [UInt8](repeating: 0xFF, count: 8) + [UInt8](repeating: 0, count: 8) }
        } else if mask.reduce(0, { $0 + $1.nonzeroBitCount }) < 8 {
            return false
        }
        return zip(zip(address, interface), mask).allSatisfy { pair, byte in pair.0 & byte == pair.1 & byte }
    }

    /// Local, or on the link of one of the Mac's network interfaces (address and netmask).
    public static func isLocal(_ bytes: [UInt8], interfaces: [(address: [UInt8], netmask: [UInt8])]) -> Bool {
        isLocal(bytes) || interfaces.contains { isOnLink(bytes, interface: $0.address, netmask: $0.netmask) }
    }

    private static func isLocalIPv4(_ bytes: [UInt8]) -> Bool {
        bytes[0] == 127 || bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254)
    }
}

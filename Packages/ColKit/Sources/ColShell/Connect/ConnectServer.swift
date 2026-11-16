import Foundation
import Network
import ColCore

/// What Connect answers: JSON, or the pairing page.
struct ConnectResponse: Sendable {
    var status: Int
    var body: Data
    var contentType = "application/json"
    var headers: [String: String] = [:]

    static func json(_ object: Any, status: Int = 200) -> ConnectResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return ConnectResponse(status: status, body: data)
    }

    static func error(_ message: String, status: Int) -> ConnectResponse {
        json(["error": message], status: status)
    }

    static let reasons = [
        200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict",
        411: "Length Required", 413: "Content Too Large", 429: "Too Many Requests", 431: "Request Header Fields Too Large",
        500: "Internal Server Error", 503: "Service Unavailable",
    ]

    /// The whole answer, on a connection that closes after it.
    var serialized: Data {
        var head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Status")\r\n"
        let fixed = [
            "Content-Type": contentType, "Content-Length": "\(body.count)", "Cache-Control": "no-store", "Connection": "close",
            "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
        ]
        for (name, value) in fixed.merging(headers, uniquingKeysWith: { _, extra in extra }).sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        return Data((head + "\r\n").utf8) + body
    }
}

/// Col Connect's server: HTTP on the local network, through Network.framework, while the user keeps Connect on. It
/// waits on its socket and does nothing between requests. Each request is read whole within limits (ConnectRequest),
/// from an address of the local network, at a bounded rate, and must carry a paired device's token; it then reaches
/// only the routes of ConnectRoute. Bonjour advertises it as `_col._tcp`.
@MainActor
final class ConnectServer {
    enum State: Equatable {
        case stopped
        case starting
        case listening(UInt16)
        /// The network is not there yet, or macOS keeps Col off the local network.
        case waiting(String)
        case failed(String)
    }

    struct Options {
        var ports: [UInt16] = Connect.preferredPorts
        /// Only this Mac can connect: for tests.
        var loopbackOnly = false
        var advertises = true
    }

    /// Answers a request a paired device made, on the main actor.
    typealias Handler = @MainActor (_ route: ConnectRoute, _ request: ConnectRequest, _ device: String) -> ConnectResponse

    private(set) var state: State = .stopped {
        didSet { if state != oldValue { onStateChange?() } }
    }
    var onStateChange: (() -> Void)?
    var handler: Handler?
    /// The paired devices' tokens, read for each request.
    var tokens: () -> [(device: String, token: String)] = { [] }
    /// Whether addresses outside the local network may connect.
    var allowsOutside: () -> Bool = { false }
    /// A paired device made a request, from this address.
    var onSeen: ((_ device: String, _ address: String) -> Void)?
    /// The page a phone opens from the pairing code, served without a token: it holds none.
    var pairingPage: () -> String = { "" }

    let options: Options
    private var listener: NWListener?
    private var waiting: [UInt64: NWConnection] = [:]
    private var pending = PendingConnections(limit: Connect.maximumConnections, perHost: Connect.maximumPendingPerAddress)
    private var lastConnection: UInt64 = 0
    /// Each address: a burst of 60 requests, then 20 a second.
    private var requests = RateLimiter(capacity: 60, perSecond: 20)
    /// Each address: ten wrong tokens, then one more every thirty seconds.
    private var failures = RateLimiter(capacity: 10, perSecond: 1.0 / 30)
    private nonisolated let queue = DispatchQueue(label: "ch.rubencatalao.islet.connect")

    init(options: Options = Options()) {
        self.options = options
    }

    var port: UInt16? {
        if case .listening(let port) = state { return port }
        return nil
    }

    func start() {
        guard listener == nil else { return }
        state = .starting
        listen(on: options.ports[...])
    }

    func stop() {
        listener?.cancel()
        listener = nil
        waiting.values.forEach { $0.cancel() }
        waiting.removeAll()
        pending.removeAll()
        state = .stopped
    }

    /// Listens on the first port free among the preferred ones, then on any.
    private func listen(on ports: ArraySlice<UInt16>) {
        let port = ports.first.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if options.loopbackOnly {
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        }
        let made: NWListener?
        if options.loopbackOnly {
            made = try? NWListener(using: parameters)
        } else {
            made = try? NWListener(using: parameters, on: port)
        }
        guard let listener = made else {
            if ports.isEmpty {
                state = .failed(String(localized: "No port is free.", bundle: .module))
            } else {
                listen(on: ports.dropFirst())
            }
            return
        }
        if options.advertises {
            listener.service = NWListener.Service(type: Connect.serviceType, txtRecord: NWTXTRecord(["path": "/v1", "api": "1"]))
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] update in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                switch update {
                case .ready:
                    self.state = .listening(listener.port?.rawValue ?? 0)
                case .waiting(let error):
                    self.state = .waiting(error.localizedDescription)
                case .failed(let error):
                    listener.cancel()
                    self.listener = nil
                    if ports.isEmpty {
                        self.state = .failed(error.localizedDescription)
                    } else {
                        self.listen(on: ports.dropFirst())
                    }
                default:
                    break
                }
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    // MARK: Connections

    /// The address of a connection's peer as bytes, with its text, or nil for one that is not an IP address.
    nonisolated static func address(of connection: NWConnection) -> (bytes: [UInt8], text: String)? {
        guard case .hostPort(let host, _) = connection.endpoint else { return nil }
        switch host {
        case .ipv4(let address): return ([UInt8](address.rawValue), "\(address)")
        case .ipv6(let address): return ([UInt8](address.rawValue), "\(address)")
        default: return nil
        }
    }

    /// The addresses of the Mac's Wi-Fi and Ethernet interfaces with their netmasks: a peer on one of their links is on
    /// the local network, even from a global IPv6 address.
    nonisolated static func linkAddresses() -> [(address: [UInt8], netmask: [UInt8])] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var found: [(address: [UInt8], netmask: [UInt8])] = []
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            let name = String(cString: interface.pointee.ifa_name)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, name.hasPrefix("en") || name.hasPrefix("bridge"),
                  let address = interface.pointee.ifa_addr, let netmask = interface.pointee.ifa_netmask
            else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                let bytes = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin_addr) { [UInt8]($0) } }
                let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin_addr) { [UInt8]($0) } }
                found.append((bytes, mask))
            case AF_INET6:
                let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin6_addr) { [UInt8]($0) } }
                let mask = netmask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin6_addr) { [UInt8]($0) } }
                found.append((bytes, mask))
            default:
                continue
            }
        }
        return found
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil, let address = Self.address(of: connection),
              LANAddress.isLocal(address.bytes) || LANAddress.isLocal(address.bytes, interfaces: Self.linkAddresses()) || allowsOutside()
        else {
            connection.cancel()
            return
        }
        lastConnection += 1
        let id = lastConnection
        guard let leaving = pending.admit(id, from: address.text, besides: 0) else {
            connection.cancel()
            return
        }
        for old in leaving { waiting.removeValue(forKey: old)?.cancel() }
        waiting[id] = connection
        connection.start(queue: queue)
        receive(connection, id: id, address: address.text, buffer: Data())
        // A request has a few seconds to arrive whole.
        DispatchQueue.main.asyncAfter(deadline: .now() + Connect.requestTimeout) { [weak self] in
            MainActor.assumeIsolated { self?.release(id) }
        }
    }

    /// A connection that never sent a whole request goes, and its slot with it.
    private func release(_ id: UInt64) {
        pending.remove(id)
        waiting.removeValue(forKey: id)?.cancel()
    }

    private nonisolated func receive(_ connection: NWConnection, id: UInt64, address: String, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch ConnectRequest.parse(buffer) {
            case .complete(let request):
                Task { @MainActor in self?.respond(to: request, on: connection, id: id, address: address) }
            case .failed(let status):
                Task { @MainActor in self?.finish(connection, id: id, with: .error("bad request", status: status)) }
            case .incomplete:
                if complete || error != nil {
                    connection.cancel()
                    Task { @MainActor in self?.release(id) }
                } else {
                    self?.receive(connection, id: id, address: address, buffer: buffer)
                }
            }
        }
    }

    private func respond(to request: ConnectRequest, on connection: NWConnection, id: UInt64, address: String) {
        guard waiting[id] != nil else { return }
        finish(connection, id: id, with: answer(request, from: address))
    }

    /// The answer to a whole request: limits first, then the token, then the route.
    func answer(_ request: ConnectRequest, from address: String, now: Date = Date()) -> ConnectResponse {
        guard requests.allow(address, now: now), !failures.isLimited(address, now: now) else {
            return ConnectResponse.error("too many requests", status: 429).with(["Retry-After": "30"])
        }
        // The page the pairing code opens holds no secret: the token stays in the address's fragment, on the phone.
        if request.method == "GET", request.path == "/connect" {
            var page = ConnectResponse(status: 200, body: Data(pairingPage().utf8), contentType: "text/html; charset=utf-8")
            page.headers["Content-Security-Policy"] = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src data:"
            return page
        }
        guard let device = ConnectAuth.device(for: request.headers["authorization"], tokens: tokens()) else {
            _ = failures.allow(address, now: now)
            return ConnectResponse.error("a paired device's token is needed: Authorization: Bearer <token>", status: 401)
                .with(["WWW-Authenticate": "Bearer realm=\"Col\""])
        }
        onSeen?(device, address)
        switch ConnectRoute.resolve(method: request.method, path: request.path) {
        case .success(let route):
            return handler?(route, request, device) ?? .error("unavailable", status: 503)
        case .failure(.methodNotAllowed):
            return .error("method not allowed", status: 405)
        case .failure(.notFound):
            return .error("not found", status: 404)
        }
    }

    private func finish(_ connection: NWConnection, id: UInt64, with response: ConnectResponse) {
        pending.remove(id)
        guard waiting.removeValue(forKey: id) != nil else { return }
        connection.send(content: response.serialized, completion: .contentProcessed { _ in connection.cancel() })
    }
}

extension ConnectResponse {
    func with(_ extra: [String: String]) -> ConnectResponse {
        var copy = self
        copy.headers.merge(extra) { _, new in new }
        return copy
    }
}

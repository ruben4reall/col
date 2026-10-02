import Foundation
import Network
import ColCore

/// The phone remote: a small web server on the local network, only while the user turns it on. Every request must
/// carry the pairing token from the QR code; without it the server answers 403 and nothing else.
@MainActor
public final class RemoteServer {
    public private(set) var port: UInt16?
    public private(set) var isRunning = false
    public var onCommand: ((RemoteCommand) -> Void)?
    /// The state to send to the phones.
    public var state: () -> RemoteState = { .idle() }
    public var onStatusChange: (() -> Void)?

    private var listener: NWListener?
    private var subscribers: [UInt64: NWConnection] = [:]
    /// Connections still sending their request: a slow or silent one is dropped, and one waiting long makes room
    /// for a newcomer when every slot is taken (`PendingConnections`).
    private var waiting: [UInt64: NWConnection] = [:]
    private var pending = PendingConnections(
        limit: RemoteServer.maximumConnections, perHost: RemoteServer.maximumPendingPerAddress
    )
    /// Connections are known by a number that is never used twice: the address of a connection that has gone can come
    /// back with a new one, and a late timer must not close the newcomer.
    private var lastConnection: UInt64 = 0
    private var heartbeat: Timer?
    private var lastSent: RemoteState?
    /// A phone or two, and the page loading: more than this at once is not a remote.
    static let maximumConnections = 16
    static let maximumSubscribers = 4
    /// A phone sends its request at once: an address with more than this many still silent is opening them on purpose.
    static let maximumPendingPerAddress = 4
    static let requestTimeout: TimeInterval = 3
    private let queue = DispatchQueue(label: "ch.rubencatalao.islet.prompter-remote")
    static let preferredPorts: [UInt16] = [7575, 7576, 7577, 7578, 7579]

    public init() {}

    public func start() {
        guard listener == nil else { return }
        startListening(on: Self.preferredPorts[...])
    }

    private func startListening(on ports: ArraySlice<UInt16>) {
        guard let port = ports.first, let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: endpointPort) else {
            return startListening(on: ports.dropFirst())
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] update in
            Task { @MainActor in
                guard let self else { return }
                switch update {
                case .ready:
                    self.port = port
                    self.isRunning = true
                    self.onStatusChange?()
                case .failed:
                    self.listener?.cancel()
                    self.listener = nil
                    self.isRunning = false
                    self.startListening(on: ports.dropFirst())
                default: break
                }
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        heartbeat?.invalidate()
        heartbeat = nil
        subscribers.values.forEach { $0.cancel() }
        subscribers.removeAll()
        waiting.values.forEach { $0.cancel() }
        waiting.removeAll()
        pending.removeAll()
        isRunning = false
        port = nil
        onStatusChange?()
    }

    /// The address to open on the phone.
    public var address: URL? {
        guard let port, let host = NetworkAddress.localIPv4() else { return nil }
        return URL(string: "http://\(host):\(port)/?token=\(PrompterPreferences.remoteToken)")
    }

    public var connectedCount: Int { subscribers.count }

    /// Sends the state to every phone, when it changed.
    public func broadcast() {
        guard !subscribers.isEmpty else { return }
        let current = state()
        guard current != lastSent, let json = try? JSONEncoder().encode(current) else { return }
        lastSent = current
        send(Data("data: ".utf8) + json + Data("\n\n".utf8))
    }

    /// Sends to every phone; one that cannot be reached any more is let go.
    private func send(_ event: Data) {
        for (id, connection) in subscribers {
            connection.send(content: event, completion: .contentProcessed { [weak self] error in
                guard error != nil else { return }
                Task { @MainActor in self?.drop(id) }
            })
        }
    }

    private func drop(_ id: UInt64) {
        subscribers.removeValue(forKey: id)?.cancel()
        if subscribers.isEmpty {
            heartbeat?.invalidate()
            heartbeat = nil
        }
        onStatusChange?()
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        var address = ""
        if case .hostPort(let host, _) = connection.endpoint {
            // Local network only: a remote peer outside private ranges is refused.
            guard NetworkAddress.isLocal(host) else {
                connection.cancel()
                return
            }
            address = "\(host)"
        }
        lastConnection += 1
        let id = lastConnection
        // Silent connections never hold a slot against a newcomer: the ones waiting longest make room.
        guard let leaving = pending.admit(id, from: address, besides: subscribers.count) else {
            connection.cancel()
            return
        }
        for old in leaving { waiting.removeValue(forKey: old)?.cancel() }
        waiting[id] = connection
        connection.start(queue: queue)
        receive(connection, id: id, buffer: Data())
        // A request has a few seconds to arrive whole.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak self] in
            MainActor.assumeIsolated { self?.release(id) }
        }
    }

    /// A connection that never sent a whole request goes, and its slot with it.
    private func release(_ id: UInt64) {
        pending.remove(id)
        waiting.removeValue(forKey: id)?.cancel()
    }

    private nonisolated func receive(_ connection: NWConnection, id: UInt64, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                Task { @MainActor in self?.respond(to: request, on: connection, id: id) }
            } else if complete || error != nil || buffer.count > 32 * 1024 {
                connection.cancel()
                Task { @MainActor in self?.release(id) }
            } else {
                self?.receive(connection, id: id, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection, id: UInt64) {
        guard waiting.removeValue(forKey: id) != nil else { return }
        pending.remove(id)
        guard RemoteToken.matches(PrompterPreferences.remoteToken, request.query["token"] ?? "") else {
            let again = String(localized: "Scan the QR code in Col's settings again.", bundle: .module)
            return send(connection, status: "403 Forbidden", type: "text/plain; charset=utf-8", body: Data(again.utf8))
        }
        switch request.path {
        case "/":
            send(connection, status: "200 OK", type: "text/html; charset=utf-8", body: Data(RemotePage.html.utf8))
        case "/state":
            let body = (try? JSONEncoder().encode(state())) ?? Data()
            send(connection, status: "200 OK", type: "application/json", body: body)
        case "/command":
            if let command = request.query["action"].flatMap(RemoteCommand.init(rawValue:)) {
                onCommand?(command)
                send(connection, status: "204 No Content", type: "text/plain", body: Data())
            } else {
                send(connection, status: "400 Bad Request", type: "text/plain", body: Data())
            }
        case "/events":
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: keep-alive\r\nX-Content-Type-Options: nosniff\r\n\r\n"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            // The oldest page goes when a new one opens past the limit: a phone reloading replaces itself.
            if subscribers.count >= Self.maximumSubscribers, let oldest = subscribers.keys.min() { drop(oldest) }
            subscribers[id] = connection
            connection.stateUpdateHandler = { [weak self] update in
                switch update {
                case .cancelled, .failed: Task { @MainActor in self?.drop(id) }
                default: break
                }
            }
            // A comment every 20 seconds keeps the stream open through the network and finds phones that left.
            if heartbeat == nil {
                heartbeat = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.send(Data(": ping\n\n".utf8)) }
                }
            }
            lastSent = nil
            broadcast()
            onStatusChange?()
        default:
            send(connection, status: "404 Not Found", type: "text/plain", body: Data())
        }
    }

    private func send(_ connection: NWConnection, status: String, type: String, body: Data) {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

enum NetworkAddress {
    /// The Mac's IPv4 address on Wi-Fi or Ethernet.
    static func localIPv4() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var candidates: [(name: String, address: String)] = []
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: interface.pointee.ifa_name)
            candidates.append((name, String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)))
        }
        return (candidates.first { $0.name.hasPrefix("en") } ?? candidates.first)?.address
    }

    /// Loopback, link-local and private addresses.
    static func isLocal(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let address):
            let bytes = [UInt8](address.rawValue)
            guard bytes.count == 4 else { return false }
            return bytes[0] == 127 || bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1]))
                || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254)
        case .ipv6(let address):
            let bytes = [UInt8](address.rawValue)
            guard bytes.count == 16 else { return false }
            if address == .loopback { return true }
            // fe80::/10 link-local, fc00::/7 unique local, and IPv4-mapped private addresses.
            if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true }
            if bytes[0] & 0xFE == 0xFC { return true }
            if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
                let mapped = Array(bytes[12..<16])
                return mapped[0] == 127 || mapped[0] == 10 || (mapped[0] == 172 && (16...31).contains(mapped[1])) || (mapped[0] == 192 && mapped[1] == 168)
            }
            return false
        default:
            return false
        }
    }
}

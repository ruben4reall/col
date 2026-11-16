import Foundation
import ColCore
import ColPrompter
import Observation
import SystemConfiguration

/// A device paired with Col Connect. Its token lives in the Keychain, never in the settings.
struct ConnectDevice: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var paired: Date
    var lastSeen: Date?
    var lastAddress: String?
}

/// Col Connect, as the settings and the island see it: on or off, the devices paired, the address to give them. Off by
/// default; turned on, its server waits on a socket, and macOS asks for the Local Network permission the first time.
@MainActor
@Observable
final class ConnectCenter {
    static let shared = ConnectCenter()

    private(set) var devices: [ConnectDevice]
    private(set) var state: ConnectServer.State = .stopped
    @ObservationIgnored let server: ConnectServer
    /// Device id to token, read from the Keychain while Connect is on.
    @ObservationIgnored private var tokens: [String: String] = [:]

    init(server: ConnectServer = ConnectServer(), devices: [ConnectDevice] = Preferences.connectDevices) {
        self.server = server
        self.devices = devices
        server.tokens = { [weak self] in
            guard let self else { return [] }
            return self.tokens.map { (device: $0.key, token: $0.value) }
        }
        server.allowsOutside = { Preferences.connectAllowsOutside }
        server.onSeen = { [weak self] device, address in self?.seen(device, from: address) }
        server.onStateChange = { [weak self] in
            guard let self else { return }
            self.state = self.server.state
        }
        server.pairingPage = { ConnectPage.html }
    }

    var isOn: Bool { Preferences.connectEnabled }

    /// Applies the setting: starts or stops the server.
    func update() {
        if Preferences.connectEnabled {
            guard state == .stopped else { return }
            tokens = Dictionary(uniqueKeysWithValues: devices.compactMap { device in
                Keychain.token(for: device.id, service: Keychain.connect).map { (device.id, $0) }
            })
            server.start()
        } else if state != .stopped {
            server.stop()
            tokens = [:]
        }
    }

    // MARK: Devices

    /// Pairs a new device: a token of its own, which only this pairing shows.
    @discardableResult
    func pair(named name: String) -> (device: ConnectDevice, token: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = ConnectDevice(id: UUID().uuidString, name: trimmed.isEmpty ? String(localized: "Device", bundle: .module) : String(trimmed.prefix(40)),
                                   paired: Date())
        let token = ConnectToken.make()
        Keychain.setToken(token, for: device.id, service: Keychain.connect)
        tokens[device.id] = token
        devices.append(device)
        Preferences.connectDevices = devices
        return (device, token)
    }

    /// The device's token, to show it again.
    func token(of id: String) -> String? {
        tokens[id] ?? Keychain.token(for: id, service: Keychain.connect)
    }

    /// A new token for the device: the old one stops working at once.
    @discardableResult
    func renewToken(of id: String) -> String? {
        guard devices.contains(where: { $0.id == id }) else { return nil }
        let token = ConnectToken.make()
        Keychain.setToken(token, for: id, service: Keychain.connect)
        if Preferences.connectEnabled { tokens[id] = token }
        return token
    }

    /// Forgets a device and its token: its requests are refused from now on.
    func unpair(_ id: String) {
        devices.removeAll { $0.id == id }
        tokens[id] = nil
        Keychain.setToken(nil, for: id, service: Keychain.connect)
        Preferences.connectDevices = devices
    }

    func rename(_ id: String, to name: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        devices[index].name = String(trimmed.prefix(40))
        Preferences.connectDevices = devices
    }

    private func seen(_ id: String, from address: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        let previous = devices[index].lastSeen
        devices[index].lastSeen = now
        devices[index].lastAddress = address
        // Saved at most once a minute: a build pushing its progress writes nothing more.
        if previous.map({ now.timeIntervalSince($0) > 60 }) ?? true { Preferences.connectDevices = devices }
    }

    // MARK: Addresses

    /// The address to give a device: the Mac's own on this network, and its Bonjour name.
    var address: String? {
        guard let port = server.port, let ip = NetworkAddress.localIPv4() else { return nil }
        return "http://\(ip):\(port)"
    }

    var bonjourAddress: String? {
        guard let port = server.port, let name = SCDynamicStoreCopyLocalHostName(nil) as String? else { return nil }
        return "http://\(name).local:\(port)"
    }

    /// What the pairing code opens on a phone: a page of this Mac's, with the token in its fragment, which the phone
    /// never sends.
    func pairingLink(token: String) -> String? {
        address.map { "\($0)/connect#\(token)" }
    }
}

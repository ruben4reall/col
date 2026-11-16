import ColCore
import CoreAudio
import Foundation
import Observation

/// Mutes the Mac's default microphone from the island: Core Audio's own mute when the device has one, else its input
/// volume turned to zero. What Col muted is written down, by device (MicrophoneMuteLedger), so that it is always undone:
/// unmuting gives back that device even if another one has become the default, turning the setting off or quitting
/// gives every one back, and a launch after Col stopped without doing so gives them back too.
/// Followed through Core Audio notifications, so a mute set elsewhere shows as well, and nothing is polled.
@MainActor
@Observable
final class MicrophoneMute {
    /// The default microphone is muted, or one Col muted still is.
    private(set) var isMuted = false
    /// The default input can be muted or turned down.
    private(set) var isAvailable = false
    /// The default microphone's name, for the Live page.
    private(set) var deviceName = ""
    /// The apps recording from the microphone now, by name, for the Live page.
    var users: [String] = []
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    @ObservationIgnored private var device: AudioObjectID = 0
    @ObservationIgnored private var systemListener: AudioListener?
    @ObservationIgnored private var deviceListeners: [AudioListener] = []

    private static let ledgerKey = "microphoneMuteLedger"
    private static let mute = CoreAudioObject.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
    private static let volume = CoreAudioObject.address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)

    private var ledger: MicrophoneMuteLedger {
        get { UserDefaults.standard.data(forKey: Self.ledgerKey).flatMap { try? JSONDecoder().decode(MicrophoneMuteLedger.self, from: $0) } ?? MicrophoneMuteLedger() }
        set {
            if newValue.isEmpty { UserDefaults.standard.removeObject(forKey: Self.ledgerKey) }
            else { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.ledgerKey) }
        }
    }

    func start() {
        guard systemListener == nil else { return }
        systemListener = AudioListener(CoreAudioObject.system, CoreAudioObject.address(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in
            self?.inputChanged()
        }
        inputChanged()
    }

    /// Stops following the microphone, and gives back every device Col muted: the setting was turned off.
    func stop() {
        restoreAll()
        systemListener = nil
        deviceListeners = []
        if isMuted { isMuted = false; onChange?(false) }
    }

    /// At launch, whatever the setting: a mute Col could not undo before it stopped (a crash, a forced quit) is
    /// undone now, if the device is there and still muted.
    func recover() {
        guard !ledger.isEmpty else { return }
        restoreAll()
    }

    /// Gives back every device Col muted that is connected: on quitting, and when the setting goes off.
    func restoreAll() {
        var ledger = self.ledger
        guard !ledger.isEmpty else { return }
        let plan = ledger.reconcile { uid in Self.device(uid: uid).map(Self.isMuted(_:)) }
        for uid in plan.restore {
            if let device = Self.device(uid: uid), let entry = ledger.entry(for: uid) { Self.unmute(device, entry) }
            ledger.forget(uid)
        }
        plan.forget.forEach { ledger.forget($0) }
        self.ledger = ledger
        read()
    }

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        if muted {
            guard device != 0, let uid = Self.uid(of: device) else { return }
            var ledger = self.ledger
            if Self.settable(device, Self.mute) {
                ledger.muted(uid, method: .mute)
                self.ledger = ledger
                CoreAudioObject.set(device, Self.mute, UInt32(1))
            } else if Self.settable(device, Self.volume) {
                let level = CoreAudioObject.get(device, Self.volume, as: Float32.self, default: 0).map(Double.init)
                ledger.muted(uid, method: .volume, volumeBefore: level)
                self.ledger = ledger
                CoreAudioObject.set(device, Self.volume, Float32(0))
            }
        } else {
            // The devices Col muted come back, wherever the default is now; the default too, if muted elsewhere.
            restoreAll()
            if device != 0, Self.isMuted(device) {
                if Self.settable(device, Self.mute) {
                    CoreAudioObject.set(device, Self.mute, UInt32(0))
                } else if Self.settable(device, Self.volume) {
                    CoreAudioObject.set(device, Self.volume, Float32(MicrophoneMuteLedger.volumeToRestore(.init(method: .volume))))
                }
            }
        }
        read()
    }

    private func inputChanged() {
        device = CoreAudioObject.get(
            CoreAudioObject.system, CoreAudioObject.address(kAudioHardwarePropertyDefaultInputDevice),
            as: AudioObjectID.self, default: 0
        ) ?? 0
        deviceName = device == 0 ? "" : CoreAudioObject.string(device, kAudioObjectPropertyName) ?? ""
        listen()
        read()
    }

    /// Listens to the default microphone and to each device Col muted, so a change made elsewhere shows.
    private func listen() {
        var devices = [device]
        devices += ledger.entries.keys.compactMap(Self.device(uid:))
        deviceListeners = Set(devices.filter { $0 != 0 }).flatMap { device in
            [Self.mute, Self.volume].compactMap { address in
                CoreAudioObject.has(device, address) ? AudioListener(device, address) { [weak self] in self?.read() } : nil
            }
        }
    }

    private func read() {
        isAvailable = device != 0 && (Self.settable(device, Self.mute) || Self.settable(device, Self.volume))
        // A device Col muted and that came back unmuted elsewhere no longer needs giving back.
        var ledger = self.ledger
        let plan = ledger.reconcile { uid in Self.device(uid: uid).map(Self.isMuted(_:)) }
        if !plan.forget.isEmpty {
            plan.forget.forEach { ledger.forget($0) }
            self.ledger = ledger
        }
        let muted = (device != 0 && Self.isMuted(device)) || !plan.restore.isEmpty
        guard muted != isMuted else { return }
        isMuted = muted
        onChange?(muted)
    }

    // MARK: Core Audio

    private static func uid(of device: AudioObjectID) -> String? {
        CoreAudioObject.string(device, kAudioDevicePropertyDeviceUID)
    }

    /// The connected device with this UID, if any.
    private static func device(uid: String) -> AudioObjectID? {
        CoreAudioObject.objects(CoreAudioObject.system, kAudioHardwarePropertyDevices).first { self.uid(of: $0) == uid }
    }

    private static func isMuted(_ device: AudioObjectID) -> Bool {
        if settable(device, mute) {
            return (CoreAudioObject.get(device, mute, as: UInt32.self, default: 0) ?? 0) != 0
        }
        if settable(device, volume) {
            return (CoreAudioObject.get(device, volume, as: Float32.self, default: 1) ?? 1) <= 0.001
        }
        return false
    }

    private static func unmute(_ device: AudioObjectID, _ entry: MicrophoneMuteLedger.Entry) {
        switch entry.method {
        case .mute: CoreAudioObject.set(device, mute, UInt32(0))
        case .volume: CoreAudioObject.set(device, volume, Float32(MicrophoneMuteLedger.volumeToRestore(entry)))
        }
    }

    private static func settable(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    /// For screenshots: a state stands in for the Mac's microphone, which is left alone.
    func showDemo(muted: Bool, users: [String], name: String = "MacBook Pro Microphone") {
        systemListener = nil
        deviceListeners = []
        isMuted = muted
        isAvailable = true
        deviceName = name
        self.users = users
    }
}

import CoreAudio
import Foundation
import Observation

/// Mutes the Mac's microphone (the default input device) for every app at once, from the island or with ⌃⌥⌘M.
/// Core Audio's own mute when the device has one; otherwise its input volume goes to zero, and back to where it was.
/// Followed through Core Audio notifications, so a mute set elsewhere shows too, and nothing is polled.
@MainActor
@Observable
final class MicrophoneMute {
    private(set) var isMuted = false
    /// The default input can be muted or turned down.
    private(set) var isAvailable = false
    /// The apps recording from the microphone now, by name, for the Live page.
    var users: [String] = []
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    @ObservationIgnored private var device: AudioObjectID = 0
    @ObservationIgnored private var systemListener: AudioListener?
    @ObservationIgnored private var deviceListeners: [AudioListener] = []

    /// The input volume before Col turned it down, kept in the settings so a restart does not lose it.
    private static let savedVolumeKey = "microphoneVolumeBeforeMute"
    private static let mute = CoreAudioObject.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
    private static let volume = CoreAudioObject.address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)

    func start() {
        guard systemListener == nil else { return }
        systemListener = AudioListener(CoreAudioObject.system, CoreAudioObject.address(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in
            self?.inputChanged()
        }
        inputChanged()
    }

    func stop() {
        systemListener = nil
        deviceListeners = []
    }

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard device != 0 else { return }
        if Self.settable(device, Self.mute) {
            CoreAudioObject.set(device, Self.mute, UInt32(muted ? 1 : 0))
        } else if Self.settable(device, Self.volume) {
            if muted {
                if let level = CoreAudioObject.get(device, Self.volume, as: Float32.self, default: 0), level > 0.001 {
                    UserDefaults.standard.set(Double(level), forKey: Self.savedVolumeKey)
                }
                CoreAudioObject.set(device, Self.volume, Float32(0))
            } else {
                let saved = UserDefaults.standard.object(forKey: Self.savedVolumeKey) as? Double ?? 0.75
                CoreAudioObject.set(device, Self.volume, Float32(saved))
                UserDefaults.standard.removeObject(forKey: Self.savedVolumeKey)
            }
        }
        read()
    }

    private func inputChanged() {
        device = CoreAudioObject.get(
            CoreAudioObject.system, CoreAudioObject.address(kAudioHardwarePropertyDefaultInputDevice),
            as: AudioObjectID.self, default: 0
        ) ?? 0
        deviceListeners = device == 0 ? [] : [Self.mute, Self.volume].compactMap { address in
            CoreAudioObject.has(device, address) ? AudioListener(device, address) { [weak self] in self?.read() } : nil
        }
        read()
    }

    private func read() {
        let canMute = device != 0 && Self.settable(device, Self.mute)
        let canTurnDown = device != 0 && Self.settable(device, Self.volume)
        isAvailable = canMute || canTurnDown
        let muted: Bool
        if canMute {
            muted = (CoreAudioObject.get(device, Self.mute, as: UInt32.self, default: 0) ?? 0) != 0
        } else if canTurnDown {
            muted = (CoreAudioObject.get(device, Self.volume, as: Float32.self, default: 1) ?? 1) <= 0.001
        } else {
            muted = false
        }
        guard muted != isMuted else { return }
        isMuted = muted
        onChange?(muted)
    }

    /// For screenshots: a state stands in for the Mac's microphone, which is left alone.
    func showDemo(muted: Bool, users: [String]) {
        stop()
        isMuted = muted
        isAvailable = true
        self.users = users
    }

    private static func settable(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}

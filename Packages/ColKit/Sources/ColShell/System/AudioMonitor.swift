import AppKit
import AudioToolbox
import CoreAudio
import ColCore

/// Follows the sound output (its volume, its mute, which device it is) and who is using the microphone, entirely
/// through Core Audio notifications: nothing is polled.
@MainActor
final class AudioMonitor {
    struct Output: Equatable {
        var id: AudioObjectID
        var name: String
        var transport: SystemGlyphs.Transport
    }

    var onVolumeChange: ((_ level: Double, _ muted: Bool) -> Void)?
    var onOutputChange: ((Output) -> Void)?
    /// Apps recording from the microphone; empty when it is free.
    var onMicrophoneChange: ((_ apps: [NSRunningApplication]) -> Void)?

    private(set) var output: Output?
    private var systemListeners: [AudioListener] = []
    private var outputListeners: [AudioListener] = []
    private var inputListeners: [AudioListener] = []
    private var inputDevice: AudioObjectID = 0
    /// The system adjusts the volume when the output changes; that is not the user turning a knob.
    private var quietUntil = Date.distantPast
    private var lastVolume: (Double, Bool)?
    private var microphoneUsers: [pid_t] = []

    func start() {
        let system = CoreAudioObject.system
        systemListeners = [
            AudioListener(system, CoreAudioObject.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
                self?.outputChanged(announce: true)
            },
            AudioListener(system, CoreAudioObject.address(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in
                self?.inputChanged()
            },
            AudioListener(system, CoreAudioObject.address(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
                self?.refreshMicrophone()
            },
        ].compactMap { $0 }
        outputChanged(announce: false)
        inputChanged()
    }

    // MARK: Output

    private func outputChanged(announce: Bool) {
        guard let device = CoreAudioObject.get(
            CoreAudioObject.system, CoreAudioObject.address(kAudioHardwarePropertyDefaultOutputDevice),
            as: AudioObjectID.self, default: 0
        ), device != 0 else { return }
        let output = Output(
            id: device,
            name: CoreAudioObject.string(device, kAudioObjectPropertyName) ?? "",
            transport: Self.transport(of: device)
        )
        guard output != self.output else { return }
        self.output = output
        quietUntil = Date().addingTimeInterval(1)
        lastVolume = currentVolume()
        outputListeners = [
            AudioListener(device, Self.volumeAddress) { [weak self] in self?.volumeChanged() },
            AudioListener(device, Self.muteAddress) { [weak self] in self?.volumeChanged() },
        ].compactMap { $0 }
        if announce { onOutputChange?(output) }
    }

    private func volumeChanged() {
        guard let volume = currentVolume() else { return }
        defer { lastVolume = volume }
        guard Date() >= quietUntil, lastVolume.map({ $0 != volume }) ?? true else { return }
        onVolumeChange?(volume.0, volume.1)
    }

    private static let volumeAddress = CoreAudioObject.address(
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput
    )
    private static let muteAddress = CoreAudioObject.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

    func currentVolume() -> (Double, Bool)? {
        guard let output,
              let level = CoreAudioObject.get(output.id, Self.volumeAddress, as: Float32.self, default: 0)
        else { return nil }
        let muted = CoreAudioObject.get(output.id, Self.muteAddress, as: UInt32.self, default: 0) ?? 0
        return (Double(level), muted != 0)
    }

    /// Sets the output volume; false when the device has no volume of its own, like most displays.
    @discardableResult
    func setVolume(_ level: Double) -> Bool {
        guard let output else { return false }
        if level > 0 { CoreAudioObject.set(output.id, Self.muteAddress, UInt32(0)) }
        return CoreAudioObject.set(output.id, Self.volumeAddress, Float32(min(max(level, 0), 1)))
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard let output else { return false }
        return CoreAudioObject.set(output.id, Self.muteAddress, UInt32(muted ? 1 : 0))
    }

    var canSetVolume: Bool {
        guard let output else { return false }
        var address = Self.volumeAddress
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(output.id, &address, &settable) == noErr && settable.boolValue
    }

    private static func transport(of device: AudioObjectID) -> SystemGlyphs.Transport {
        let type = CoreAudioObject.get(device, CoreAudioObject.address(kAudioDevicePropertyTransportType), as: UInt32.self, default: 0) ?? 0
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        default: return .other
        }
    }

    // MARK: Choosing the output

    struct Device: Identifiable, Equatable {
        var id: AudioObjectID
        var name: String
        var transport: SystemGlyphs.Transport
    }

    /// Every device that can play sound, for the picker in the player.
    func outputDevices() -> [Device] {
        CoreAudioObject.objects(CoreAudioObject.system, kAudioHardwarePropertyDevices).compactMap { device in
            var address = CoreAudioObject.address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
            let name = CoreAudioObject.string(device, kAudioObjectPropertyName) ?? ""
            // Virtual aggregate devices made by other apps are noise here.
            guard !name.isEmpty, !name.hasPrefix("CADefault") else { return nil }
            return Device(id: device, name: name, transport: Self.transport(of: device))
        }
    }

    func setOutput(_ device: AudioObjectID) {
        CoreAudioObject.set(CoreAudioObject.system, CoreAudioObject.address(kAudioHardwarePropertyDefaultOutputDevice), device)
    }

    // MARK: Microphone

    private func inputChanged() {
        inputDevice = CoreAudioObject.get(
            CoreAudioObject.system, CoreAudioObject.address(kAudioHardwarePropertyDefaultInputDevice),
            as: AudioObjectID.self, default: 0
        ) ?? 0
        inputListeners = [
            AudioListener(inputDevice, CoreAudioObject.address(kAudioDevicePropertyDeviceIsRunningSomewhere)) { [weak self] in
                self?.refreshMicrophone()
            },
        ].compactMap { $0 }
        refreshMicrophone()
    }

    /// Finds the processes recording right now. Core Audio lists them since macOS 14.2.
    private func refreshMicrophone() {
        let running = CoreAudioObject.get(
            inputDevice, CoreAudioObject.address(kAudioDevicePropertyDeviceIsRunningSomewhere), as: UInt32.self, default: 0
        ) ?? 0
        var users: [pid_t] = []
        if running != 0 {
            let me = ProcessInfo.processInfo.processIdentifier
            for process in CoreAudioObject.objects(CoreAudioObject.system, kAudioHardwarePropertyProcessObjectList) {
                let recording = CoreAudioObject.get(
                    process, CoreAudioObject.address(kAudioProcessPropertyIsRunningInput), as: UInt32.self, default: 0
                ) ?? 0
                guard recording != 0,
                      let pid = CoreAudioObject.get(process, CoreAudioObject.address(kAudioProcessPropertyPID), as: pid_t.self, default: 0),
                      pid != me
                else { continue }
                users.append(pid)
            }
        }
        users.sort()
        guard users != microphoneUsers else { return }
        microphoneUsers = users
        onMicrophoneChange?(users.compactMap(Self.application(for:)))
    }

    /// The app behind a process, climbing to its parent when the recorder is a helper.
    private static func application(for pid: pid_t) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return NSRunningApplication(processIdentifier: pid) }
        let parent = info.kp_eproc.e_ppid
        if parent > 1, let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular { return app }
        return NSRunningApplication(processIdentifier: pid)
    }

    /// Mutes or unmutes the microphone for every app at once.
    func setMicrophoneMuted(_ muted: Bool) {
        CoreAudioObject.set(inputDevice, CoreAudioObject.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput), UInt32(muted ? 1 : 0))
    }

    var isMicrophoneMuted: Bool {
        (CoreAudioObject.get(inputDevice, CoreAudioObject.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput), as: UInt32.self, default: 0) ?? 0) != 0
    }
}

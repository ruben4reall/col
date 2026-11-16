import AppKit
import AudioToolbox
import ColCore
import CoreAudio
import Foundation

/// The levels of the sound that plays, for bars that follow it: the closed island's equalizer and the player's
/// spectrum. Listens only while the setting is on, music plays and a view with bars shows; then a Core Audio tap
/// copies the player's sound (or the Mac's, when the player's own cannot be told apart), and it is analysed on the
/// spot, thirty times a second, in 24 bands. Nothing is recorded, kept or sent.
@MainActor
final class SoundLevels {
    static let shared = SoundLevels()

    /// 24 bands from the bass up, each from 0 to 1. Nil while the bars dance on their own: the setting is off, macOS
    /// cannot tap the sound, or what plays is silent.
    private(set) var levels: [Float]?
    static let bands = 24

    private var subscribers: [ObjectIdentifier: ([Float]?) -> Void] = [:]
    private var tap: AnyObject?
    private var tappedPID: pid_t = -1
    private var playing = false
    private var pid: pid_t = 0
    private var linger: Task<Void, Never>?
    /// Bumped at each start and stop, so levels a stopped tap still sends are dropped.
    private var generation = 0
    /// Levels in a row that were all silent.
    private var silentFrames = 0
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SoundLevels.shared.evaluate() }
        }
    }

    /// Whether this Mac can tap the sound of another app: macOS 14.2 and later.
    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    /// The player changed state.
    func playerChanged(playing: Bool, pid: pid_t) {
        guard playing != self.playing || pid != self.pid else { return }
        self.playing = playing
        self.pid = pid
        evaluate()
    }

    /// A view with bars appeared: it gets the levels as they come, and nil when they stop.
    func subscribe(_ owner: AnyObject, _ handler: @escaping ([Float]?) -> Void) {
        subscribers[ObjectIdentifier(owner)] = handler
        evaluate()
    }

    func unsubscribe(_ owner: AnyObject) {
        guard subscribers.removeValue(forKey: ObjectIdentifier(owner)) != nil else { return }
        evaluate()
    }

    /// The user answered macOS's question: a tap made before the answer is made again, so it hears the sound.
    func permissionChanged() {
        if tap != nil { start() } else { evaluate() }
    }

    /// Listens for a moment, so that macOS asks for the permission where its question cannot be asked directly.
    func listenOnce() {
        guard tap == nil, Self.isSupported else { return }
        start()
        linger = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private var wanted: Bool {
        Preferences.barsFollowSound && playing && !subscribers.isEmpty && AudioCapturePermission.status != .denied
    }

    private func evaluate() {
        if wanted {
            linger?.cancel()
            linger = nil
            if tap == nil || tappedPID != pid { start() }
        } else if tap != nil {
            // Views come and go as the island opens and closes: the tap waits a moment before it is taken down,
            // unless the music or the setting stopped.
            let immediately = !Preferences.barsFollowSound || !playing
            linger?.cancel()
            linger = Task { @MainActor [weak self] in
                if !immediately { try? await Task.sleep(for: .seconds(3)) }
                guard let self, !Task.isCancelled, !self.wanted else { return }
                self.stop()
            }
        }
    }

    private func start() {
        stop()
        guard #available(macOS 14.2, *) else { return }
        generation += 1
        let generation = generation
        tappedPID = pid
        tap = SoundTap(pid: pid, bands: Self.bands) { levels in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { SoundLevels.shared.receive(levels, generation: generation) }
            }
        }
    }

    private func stop() {
        generation += 1
        if #available(macOS 14.2, *) { (tap as? SoundTap)?.stop() }
        tap = nil
        tappedPID = -1
        silentFrames = 0
        publish(nil)
    }

    private func receive(_ levels: [Float], generation: Int) {
        guard generation == self.generation else { return }
        // A second and a half of silence while music plays: a quiet passage, or a tap macOS keeps silent. The bars
        // dance on their own until sound comes.
        if levels.allSatisfy({ $0 < 0.02 }) {
            silentFrames += 1
            if silentFrames > 45 { publish(nil) }
            return
        }
        silentFrames = 0
        publish(levels)
    }

    private func publish(_ levels: [Float]?) {
        guard levels != nil || self.levels != nil else { return }
        self.levels = levels
        for handler in subscribers.values { handler(levels) }
    }
}

/// A Core Audio tap on the sound of one app, or of the whole Mac, read through a private aggregate device whose
/// only input is the tap: no microphone is ever opened.
@available(macOS 14.2, *)
private final class SoundTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "ch.rubencatalao.col.sound", qos: .userInteractive)

    /// The analysis, touched only on the audio queue.
    private final class Analysis: @unchecked Sendable {
        let analyzer: SpectrumAnalyzer
        let deliver: @Sendable ([Float]) -> Void

        init(analyzer: SpectrumAnalyzer, deliver: @escaping @Sendable ([Float]) -> Void) {
            self.analyzer = analyzer
            self.deliver = deliver
        }
    }

    /// Nil when macOS will not make the tap.
    init?(pid: pid_t, bands: Int, deliver: @escaping @Sendable ([Float]) -> Void) {
        let processes = Self.audioProcesses(of: pid)
        let description = processes.isEmpty
            ? CATapDescription(monoGlobalTapButExcludeProcesses: Self.audioProcesses(of: getpid()))
            : CATapDescription(monoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "Col"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown else { return nil }

        let format = CoreAudioObject.get(tapID, CoreAudioObject.address(kAudioTapPropertyFormat), as: AudioStreamBasicDescription.self,
                                         default: AudioStreamBasicDescription())
        guard let format, format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              let analyzer = SpectrumAnalyzer(bands: bands, sampleRate: format.mSampleRate)
        else {
            stop()
            return nil
        }
        let analysis = Analysis(analyzer: analyzer, deliver: deliver)
        let channels = Int(max(format.mChannelsPerFrame, 1))
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        let block: AudioDeviceIOBlock = { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let data = first.mData else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            let due: Bool
            if interleaved {
                let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
                due = analysis.analyzer.append(interleaved: samples, frames: count / channels, channels: channels)
            } else {
                // Separate channels: the first one is enough to see the music move.
                due = analysis.analyzer.append(samples, count: Int(first.mDataByteSize) / MemoryLayout<Float>.size)
            }
            if due { analysis.deliver(analysis.analyzer.analyze()) }
        }
        // The tap alone first. Should macOS want a clock beside it, the output device lends its own, but only a device
        // without inputs: an input of the aggregate would open a microphone (AirPods, a headset).
        let clocks: [String?] = [nil] + [Self.outputWithoutInputs()].compactMap { $0 }
        guard clocks.contains(where: { open(tap: description.uuid, clock: $0, block: block) }) else {
            stop()
            return nil
        }
    }

    /// Makes the aggregate device around the tap and starts reading it; false, with nothing left behind, when macOS
    /// refuses.
    private func open(tap: UUID, clock: String?, block: @escaping AudioDeviceIOBlock) -> Bool {
        var properties: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Col",
            kAudioAggregateDeviceUIDKey: "ch.rubencatalao.col.sound.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: clock.map { [[kAudioSubDeviceUIDKey: $0] as [String: Any]] } ?? [],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tap.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        if let clock { properties[kAudioAggregateDeviceMainSubDeviceKey] = clock }
        guard AudioHardwareCreateAggregateDevice(properties as CFDictionary, &deviceID) == noErr, deviceID != kAudioObjectUnknown else {
            deviceID = AudioObjectID(kAudioObjectUnknown)
            return false
        }
        if AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue, block) == noErr, let procID, AudioDeviceStart(deviceID, procID) == noErr {
            return true
        }
        if let procID { AudioDeviceDestroyIOProcID(deviceID, procID) }
        procID = nil
        AudioHardwareDestroyAggregateDevice(deviceID)
        deviceID = AudioObjectID(kAudioObjectUnknown)
        return false
    }

    /// The UID of the default output device, when it has no input streams.
    private static func outputWithoutInputs() -> String? {
        guard let device = CoreAudioObject.get(CoreAudioObject.system, CoreAudioObject.address(kAudioHardwarePropertyDefaultOutputDevice),
                                               as: AudioObjectID.self, default: 0), device != kAudioObjectUnknown
        else { return nil }
        var address = CoreAudioObject.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size == 0 else { return nil }
        return CoreAudioObject.string(device, kAudioDevicePropertyDeviceUID)
    }

    func stop() {
        if let procID, deviceID != kAudioObjectUnknown {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        procID = nil
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
        deviceID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    /// The Core Audio objects of an app that is playing sound: the app itself, and its helpers (a browser plays from
    /// a helper process whose bundle starts with the browser's). Empty when none plays, and the whole Mac is tapped.
    static func audioProcesses(of pid: pid_t) -> [AudioObjectID] {
        guard pid > 0 else { return [] }
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let objects = CoreAudioObject.objects(CoreAudioObject.system, kAudioHardwarePropertyProcessObjectList)
        return objects.filter { object in
            let owner = CoreAudioObject.get(object, CoreAudioObject.address(kAudioProcessPropertyPID), as: pid_t.self, default: 0) ?? 0
            let id = CoreAudioObject.string(object, kAudioProcessPropertyBundleID) ?? ""
            let running = CoreAudioObject.get(object, CoreAudioObject.address(kAudioProcessPropertyIsRunningOutput), as: UInt32.self, default: 0) ?? 0
            let ours = owner == pid || (bundle.map { !id.isEmpty && id.hasPrefix($0 + ".") } ?? false)
            return ours && (running != 0 || pid == getpid())
        }
    }
}

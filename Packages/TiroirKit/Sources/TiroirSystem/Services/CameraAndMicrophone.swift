import CoreAudio
import CoreMediaIO
import Foundation

/// Tells whether any app uses a camera or a microphone, from each device's own "running somewhere" flag: CoreAudio's
/// for the audio devices that take sound in, CoreMediaIO's for cameras. Listeners exist only between `start()` and
/// `stop()`, and follow devices that come and go. Tiroir never opens a device, never records, and needs no Camera or
/// Microphone permission for this.
@MainActor
final class CameraAndMicrophone {
    /// Called when a device starts or stops running, or when devices come or go.
    var onChange: (@MainActor () -> Void)?
    private(set) var isRunning = false
    private var microphones: [AudioObjectID] = []
    private var cameras: [CMIOObjectID] = []
    // Each listener is kept, because removing one takes the very block that was added.
    private var microphoneListener: AudioObjectPropertyListenerBlock?
    private var microphoneListListener: AudioObjectPropertyListenerBlock?
    private var cameraListener: CMIOObjectPropertyListenerBlock?
    private var cameraListListener: CMIOObjectPropertyListenerBlock?

    init() {}

    /// Whether a device that takes sound in, or a camera, runs for any app right now.
    var isInUse: Bool {
        microphones.contains(where: Self.isRunning(microphone:)) || cameras.contains(where: Self.isRunning(camera:))
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        let devicesChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.followMicrophones()
                self?.onChange?()
            }
        }
        let cameraChanged: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        let camerasChanged: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.followCameras()
                self?.onChange?()
            }
        }
        microphoneListener = changed
        microphoneListListener = devicesChanged
        cameraListener = cameraChanged
        cameraListListener = camerasChanged

        var audioDevices = Self.audioAddress(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &audioDevices, .main, devicesChanged)
        var videoDevices = Self.videoAddress(kCMIOHardwarePropertyDevices)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &videoDevices, .main, camerasChanged)
        followMicrophones()
        followCameras()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        unfollowMicrophones()
        unfollowCameras()
        if let block = microphoneListListener {
            var address = Self.audioAddress(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        if let block = cameraListListener {
            var address = Self.videoAddress(kCMIOHardwarePropertyDevices)
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, block)
        }
        microphoneListener = nil
        microphoneListListener = nil
        cameraListener = nil
        cameraListListener = nil
    }

    // MARK: Microphones

    private func followMicrophones() {
        unfollowMicrophones()
        guard isRunning, let block = microphoneListener else { return }
        microphones = Self.audioInputDevices()
        for device in microphones {
            var address = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
        }
    }

    private func unfollowMicrophones() {
        if let block = microphoneListener {
            for device in microphones {
                var address = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
            }
        }
        microphones = []
    }

    private static func audioAddress(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Every audio device with an input stream: built-in and external microphones, headsets.
    private static func audioInputDevices() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = audioAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride).filter { device in
            var streams = audioAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            var streamsSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamsSize) == noErr && streamsSize > 0
        }
    }

    private static func isRunning(microphone device: AudioObjectID) -> Bool {
        var address = audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    // MARK: Cameras

    private func followCameras() {
        unfollowCameras()
        guard isRunning, let block = cameraListener else { return }
        cameras = Self.videoDevices()
        for camera in cameras {
            var address = Self.videoAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectAddPropertyListenerBlock(camera, &address, .main, block)
        }
    }

    private func unfollowCameras() {
        if let block = cameraListener {
            for camera in cameras {
                var address = Self.videoAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
                CMIOObjectRemovePropertyListenerBlock(camera, &address, .main, block)
            }
        }
        cameras = []
    }

    private static func videoAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    /// Every camera that says whether it runs.
    private static func videoDevices() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = videoAddress(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.stride)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return [] }
        var running = videoAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var result: [CMIOObjectID] = []
        for device in devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.stride) where CMIOObjectHasProperty(device, &running) {
            result.append(device)
        }
        return result
    }

    private static func isRunning(camera device: CMIOObjectID) -> Bool {
        var address = videoAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &running) == noErr && running != 0
    }
}

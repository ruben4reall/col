import CoreMediaIO
import Foundation

/// Knows when any camera is in use, through Core Media IO notifications. It never opens a camera, so it needs no
/// permission.
@MainActor
final class CameraMonitor {
    var onChange: ((_ inUse: Bool) -> Void)?
    private(set) var inUse = false
    private var devices: [CMIOObjectID] = []
    private var listeners: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []

    func start() {
        var address = Self.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, block) == noErr {
            listeners.append((CMIOObjectID(kCMIOObjectSystemObject), address, block))
        }
        devicesChanged()
    }

    private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private func devicesChanged() {
        // Keep the system listener, replace the per-device ones.
        for (object, address, block) in listeners.dropFirst() {
            var address = address
            CMIOObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners = Array(listeners.prefix(1))

        var address = Self.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size)
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids)
        devices = ids

        for device in ids {
            var running = Self.address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            if CMIOObjectAddPropertyListenerBlock(device, &running, .main, block) == noErr {
                listeners.append((device, running, block))
            }
        }
        refresh()
    }

    private func refresh() {
        let running = devices.contains { device in
            var address = Self.address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            var value: UInt32 = 0
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
            return status == noErr && value != 0
        }
        guard running != inUse else { return }
        inUse = running
        onChange?(running)
    }
}

import Foundation
import IOBluetooth
import ColCore

/// Battery levels of connected Bluetooth accessories. AirPods and Beats report them through properties IOBluetooth
/// does not document; they are read defensively and simply missing when a device does not have them.
@MainActor
enum BluetoothAccessories {
    /// The connected Bluetooth device an audio output belongs to, matched by name.
    private static func device(forName name: String) -> IOBluetoothDevice? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        let wanted = name.lowercased()
        return devices.first(where: { device in
            guard device.isConnected(), let deviceName = device.name?.lowercased() else { return false }
            return deviceName == wanted || wanted.contains(deviceName) || deviceName.contains(wanted)
        })
    }

    /// Which headphones these are: Apple's product ID when the device reports one, its name otherwise.
    static func model(forName name: String) -> HeadphoneModel? {
        if let device = device(forName: name), device.responds(to: Selector(("productID"))),
           let id = device.value(forKey: "productID") as? NSNumber, let model = HeadphoneModel(productID: id.intValue) {
            return model
        }
        return HeadphoneModel(name: name)
    }

    static func battery(forName name: String) -> AccessoryBattery? {
        guard let device = device(forName: name) else { return nil }
        func read(_ key: String) -> Int? {
            guard device.responds(to: Selector(key)), let value = device.value(forKey: key) as? NSNumber else { return nil }
            return AccessoryBattery.level(value.intValue)
        }
        let battery = AccessoryBattery(
            left: read("batteryPercentLeft"),
            right: read("batteryPercentRight"),
            caseLevel: read("batteryPercentCase"),
            single: read("batteryPercentSingle") ?? read("batteryPercentCombined")
        )
        return battery.isEmpty ? nil : battery
    }
}

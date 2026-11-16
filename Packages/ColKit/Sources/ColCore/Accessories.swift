import Foundation

/// What kind of accessory reports a battery, for its symbol.
public enum AccessoryKind: String, Equatable, Sendable {
    case mouse, keyboard, trackpad, headphones, gameController, pencil, other

    /// From the product's name, else the HID usage it reports (generic desktop page: 2 mouse, 6 keyboard, 4 and 5
    /// joystick and game pad).
    public init(product: String, usagePage: Int? = nil, usage: Int? = nil) {
        let name = product.lowercased()
        if name.contains("trackpad") { self = .trackpad }
        else if name.contains("mouse") { self = .mouse }
        else if name.contains("keyboard") { self = .keyboard }
        else if name.contains("pencil") { self = .pencil }
        else if ["controller", "gamepad", "dualsense", "dualshock", "joy-con"].contains(where: name.contains) { self = .gameController }
        else if ["airpods", "beats", "headphones", "earbuds"].contains(where: name.contains) { self = .headphones }
        else if usagePage == 1, usage == 2 { self = .mouse }
        else if usagePage == 1, usage == 6 { self = .keyboard }
        else if usagePage == 1, usage == 4 || usage == 5 { self = .gameController }
        else { self = .other }
    }

    public var symbol: String {
        switch self {
        case .mouse: "magicmouse.fill"
        case .keyboard: "keyboard.fill"
        case .trackpad: "rectangle.and.hand.point.up.left.fill"
        case .headphones: "headphones"
        case .gameController: "gamecontroller.fill"
        case .pencil: "applepencil"
        case .other: "antenna.radiowaves.left.and.right"
        }
    }
}

/// An accessory's battery, as IOKit reports it for Bluetooth mice, keyboards, trackpads and other HID devices
/// (`BatteryPercent` on their AppleDeviceManagementHIDEventService).
public struct AccessoryLevel: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: AccessoryKind
    /// From 1 to 100.
    public var percent: Int

    public init(id: String, name: String, kind: AccessoryKind, percent: Int) {
        self.id = id
        self.name = name
        self.kind = kind
        self.percent = percent
    }

    /// Reads a service's registry properties; nil without a name or a battery level that makes sense.
    public static func parse(_ properties: [String: Any]) -> AccessoryLevel? {
        guard let name = (properties["Product"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let raw = (properties["BatteryPercent"] as? NSNumber)?.intValue, let percent = AccessoryBattery.level(raw)
        else { return nil }
        let address = (properties["DeviceAddress"] as? String) ?? (properties["SerialNumber"] as? String)
        let id = address.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? name
        let kind = AccessoryKind(
            product: name,
            usagePage: (properties["PrimaryUsagePage"] as? NSNumber)?.intValue,
            usage: (properties["PrimaryUsage"] as? NSNumber)?.intValue
        )
        return AccessoryLevel(id: id, name: name, kind: kind, percent: percent)
    }

    /// Several services of one device (a keyboard with a trackpad, say) report the same battery: one entry each,
    /// sorted by name.
    public static func unique(_ levels: [AccessoryLevel]) -> [AccessoryLevel] {
        var seen: Set<String> = []
        return levels.filter { seen.insert($0.id).inserted }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}

/// Says once when an accessory runs low: when it falls under the threshold, or connects already under it. It says it
/// again only after the accessory has been charged above it.
public struct LowBatteryWatch: Equatable, Sendable {
    public static let threshold = 15
    private var warned: Set<String> = []

    public init() {}

    /// The accessories to warn about now, given every level read.
    public mutating func update(_ levels: [AccessoryLevel]) -> [AccessoryLevel] {
        var alerts: [AccessoryLevel] = []
        for level in levels {
            if level.percent < Self.threshold {
                if warned.insert(level.id).inserted { alerts.append(level) }
            } else {
                warned.remove(level.id)
            }
        }
        return alerts
    }
}

import AppKit
import TiroirCore

/// Generic icons instead of the menu bar (spec 13): the website's pictures and the README's are real captures of
/// Tiroir, and demo mode guarantees they never show anyone's own apps. Nothing in the real menu bar moves.
@MainActor
public final class DemoEngine: MenuBarEngine {
    public let kind = EngineKind.demo
    public let granularity = Granularity.icon
    public let status = EngineStatus.ready
    public var onStatusChange: (@MainActor (EngineStatus) -> Void)?
    /// The last plan applied, for the interface to draw.
    public private(set) var appliedPlan = VisibilityPlan.showEverything
    /// The icons opened, most recent last.
    public private(set) var opened: [IconID] = []

    public struct DemoApp: Sendable {
        public var bundleID: String
        public var name: String
        public var symbol: String
        public var width: CGFloat
    }

    /// Twelve made-up apps covering Smart Sort's most common drawers.
    public static let apps: [DemoApp] = [
        DemoApp(bundleID: "com.example.cloud", name: "Cloud Drive", symbol: "cloud.fill", width: 34),
        DemoApp(bundleID: "com.example.photosync", name: "Photo Sync", symbol: "photo.on.rectangle.angled", width: 34),
        DemoApp(bundleID: "com.example.vpn", name: "Private VPN", symbol: "lock.shield.fill", width: 32),
        DemoApp(bundleID: "com.example.passwords", name: "Passwords", symbol: "key.fill", width: 32),
        DemoApp(bundleID: "com.example.chat", name: "Team Chat", symbol: "bubble.left.and.bubble.right.fill", width: 36),
        DemoApp(bundleID: "com.example.mailbridge", name: "Mail Bridge", symbol: "envelope.fill", width: 34),
        DemoApp(bundleID: "com.example.assistant", name: "Assistant", symbol: "sparkles", width: 32),
        DemoApp(bundleID: "com.example.dictation", name: "Dictation", symbol: "waveform", width: 32),
        DemoApp(bundleID: "com.example.containers", name: "Containers", symbol: "shippingbox.fill", width: 32),
        DemoApp(bundleID: "com.example.devserver", name: "Dev Server", symbol: "terminal.fill", width: 32),
        DemoApp(bundleID: "com.example.music", name: "Mini Player", symbol: "music.note", width: 30),
        DemoApp(bundleID: "com.example.stats", name: "System Stats", symbol: "cpu", width: 34),
    ]

    /// Where Smart Sort puts each made-up app.
    public static let categories: [String: CategoryID] = [
        "com.example.cloud": .files, "com.example.photosync": .files,
        "com.example.vpn": .security, "com.example.passwords": .security,
        "com.example.chat": .messages, "com.example.mailbridge": .messages,
        "com.example.assistant": .ai, "com.example.dictation": .ai,
        "com.example.containers": .developer, "com.example.devserver": .developer,
        "com.example.music": .media, "com.example.stats": .system,
    ]

    public init() {}

    public func start() async {}

    public func scan() async -> MenuBarSnapshot {
        var icons: [MenuBarIcon] = []
        var x: CGFloat = 1512
        func add(_ id: IconID, _ name: String, _ label: String?, width: CGFloat, kind: IconKind, movable: Bool) {
            x -= width
            icons.append(MenuBarIcon(id: id, ownerName: name, label: label, frame: CGRect(x: x, y: 0, width: width, height: 33),
                                     isMovable: movable, kind: kind))
        }
        add(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock"), "Control Center", "Clock", width: 151, kind: .system, movable: false)
        add(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.controlcenter"), "Control Center", "Control Center", width: 42, kind: .system, movable: false)
        add(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.wifi"), "Control Center", "Wi-Fi", width: 38, kind: .system, movable: true)
        add(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.battery"), "Control Center", "Battery", width: 42, kind: .system, movable: true)
        for app in Self.apps {
            add(IconID(bundleID: app.bundleID), app.name, nil, width: app.width, kind: .app, movable: true)
        }
        return MenuBarSnapshot(icons: icons)
    }

    public func apply(_ plan: VisibilityPlan) async -> ApplyReport {
        appliedPlan = plan
        return ApplyReport(moved: plan.concealed.sorted())
    }

    public func open(_ icon: IconID, anchor: CGRect?) async throws {
        opened.append(icon)
    }

    public func restore() {}

    /// The made-up apps' names and icons, drawn from SF Symbols on a neutral tile.
    public static func directoryOverrides() -> [String: AppInfo] {
        var overrides: [String: AppInfo] = [:]
        for app in apps {
            overrides[app.bundleID] = AppInfo(
                bundleID: app.bundleID, name: app.name, icon: tile(symbol: app.symbol), bundleURL: nil,
                appStoreCategory: nil, developer: "Example")
        }
        return overrides
    }

    /// A rounded tile with a symbol, the size of an app icon.
    static func tile(symbol: String) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 14, yRadius: 14)
            NSColor(white: 0.18, alpha: 1).setFill()
            path.fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
                .applying(.init(paletteColors: [NSColor(white: 0.95, alpha: 1)]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let size = image.size
                image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }
}

import AppKit
import OSLog
import TiroirCore
import TiroirSystem
import TiroirUI

/// A plain text report for a bug report (Settings, General). It holds what a maintainer needs to understand a
/// problem: the Mac, macOS, the engine, what Tiroir sees in the menu bar (bundle identifiers, never labels or window
/// titles) and Tiroir's own recent log messages. It never leaves the Mac by itself.
@MainActor
enum Diagnostics {
    static func report(interface: InterfaceModel, engine: MenuBarEngine, snapshot: MenuBarSnapshot) -> String {
        let settings = interface.settings
        var lines = [
            "Tiroir \(interface.appVersion)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Mac: \(hardwareModel())",
            "Engine: \(engine.kind.rawValue), \(engine.status)",
            "Accessibility: \(interface.accessibilityTrusted ? "granted" : "not granted")",
            "Runs from /Applications: \(interface.isInApplications ? "yes" : "no")",
            "Displays: " + NSScreen.screens.map { screen in
                "\(Int(screen.frame.width))x\(Int(screen.frame.height))" + (screen.safeAreaInsets.top > 0 ? " (notch)" : "")
            }.joined(separator: ", "),
            "Drawers: \(settings.layout.drawers.count), new icons: \(settings.layout.newIconPolicy)",
            "Modes: focus \(interface.isFocusOn), showing everything \(interface.isShowingEverything)",
        ]
        if let capacity = interface.capacity {
            lines.append("Room: \(Int(capacity.used)) of \(Int(capacity.room)) points, overflow \(capacity.overflow.count)")
        }
        lines.append("")
        lines.append("Icons, right to left (\(snapshot.icons.count)):")
        for icon in snapshot.icons {
            let place: String = interface.row(icon.id).map { row in
                switch interface.placement(of: row) {
                case .menuBar: "menu bar"
                case .hidden: "hidden"
                case .drawer: "drawer"
                }
            } ?? "unknown"
            let frame = icon.frame
            lines.append("- \(icon.id.description) \(icon.kind) \(icon.isMovable ? "movable" : "fixed") \(icon.isOnScreen ? "shown" : "off screen") "
                         + "x \(Int(frame.minX)) w \(Int(frame.width)), \(place)")
        }
        if !interface.failedMoves.isEmpty {
            lines.append("")
            lines.append("Could not move: " + interface.failedMoves.map(\.description).joined(separator: ", "))
        }
        let messages = recentMessages()
        if !messages.isEmpty {
            lines.append("")
            lines.append("Recent messages:")
            lines.append(contentsOf: messages)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #if arch(arm64)
        return name + ", Apple silicon"
        #else
        return name + ", Intel"
        #endif
    }

    /// Tiroir's own log of the last half hour, newest last, at most 80 lines.
    private static func recentMessages() -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let since = store.position(date: Date().addingTimeInterval(-1800))
        let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
        guard let entries = try? store.getEntries(at: since, matching: predicate) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { entry in
            "\(formatter.string(from: entry.date)) \(entry.category): \(entry.composedMessage)"
        }
        return Array(lines.suffix(80))
    }
}

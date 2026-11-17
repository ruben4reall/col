import CoreGraphics
import Foundation
@testable import TiroirCore

/// An icon at `x` (its left edge), 30 points wide unless told otherwise, in a menu bar 33 points tall.
func icon(
    _ bundleID: String, key: String = "", x: CGFloat, width: CGFloat = 30, name: String? = nil, label: String? = nil,
    kind: IconKind = .app, movable: Bool = true, onScreen: Bool = true
) -> MenuBarIcon {
    MenuBarIcon(
        id: IconID(bundleID: bundleID, key: key), ownerName: name ?? bundleID.components(separatedBy: ".").last ?? bundleID,
        label: label, frame: CGRect(x: x, y: 0, width: width, height: 33), isOnScreen: onScreen, isMovable: movable,
        kind: kind)
}

/// The icons of a MacBook's menu bar, from the clock leftwards, as Tiroir saw Ruben's on 2026-09-27.
func sampleBar() -> MenuBarSnapshot {
    MenuBarSnapshot(icons: [
        icon("com.apple.controlcenter", key: "com.apple.menuextra.clock", x: 1363, width: 151, label: "Clock", kind: .system, movable: false),
        icon("com.apple.controlcenter", key: "com.apple.menuextra.controlcenter", x: 1321, width: 42, label: "Control Center", kind: .system, movable: false),
        icon("com.apple.Spotlight", x: 1289, width: 32, name: "Spotlight", kind: .system),
        icon("com.apple.controlcenter", key: "com.apple.menuextra.wifi", x: 1251, width: 38, label: "Wi-Fi", kind: .system),
        icon("com.apple.controlcenter", key: "com.apple.menuextra.battery", x: 1209, width: 42, label: "Battery", kind: .system),
        icon("com.apple.TextInputMenuAgent", x: 1165, width: 44, name: "Input Menu", kind: .system),
        icon("com.apple.controlcenter", key: "com.apple.menuextra.sound", x: 1127, width: 38, label: "Sound", kind: .system),
        icon("com.google.drivefs", x: 1095, width: 32, name: "Google Drive"),
        icon("com.protonmail.bridge", x: 1057, width: 38, name: "Proton Mail Bridge"),
        icon("com.anthropic.claudefordesktop", x: 1017, width: 40, name: "Claude"),
        icon("ch.rubencatalao.pli", x: 979, width: 38, name: "Pli"),
    ])
}

/// English category names, as the interface would give them.
func englishName(_ category: CategoryID) -> String {
    switch category {
    case .files: "Files & Cloud"
    case .security: "Security & VPN"
    case .messages: "Messages"
    case .ai: "AI"
    case .developer: "Developer"
    case .media: "Music & Video"
    case .devices: "Displays & Devices"
    case .system: "System"
    case .productivity: "Productivity"
    case .utilities: "Utilities"
    case .design: "Design"
    case .games: "Games"
    case .other: "Other"
    }
}

/// Identifiers handed out in order, so proposals can be compared.
final class SequentialIDs: @unchecked Sendable {
    private var next = 0
    func make() -> UUID {
        next += 1
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", next))!
    }
}

/// A name for a test's own preferences domain. A name that is an absolute path makes macOS keep the domain in that file,
/// here in the temporary folder: nothing reaches ~/Library/Preferences, even the empty file cfprefsd can write back
/// after a test has removed its domain.
func scratchDefaultsName() -> String {
    let folder = FileManager.default.temporaryDirectory.appending(path: "tiroir-tests", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: UUID().uuidString).path
}

/// Removes a preferences domain a test made with `scratchDefaultsName()`, and its file.
func discardDefaults(_ name: String) {
    UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    CFPreferencesAppSynchronize(name as CFString)
    try? FileManager.default.removeItem(atPath: name + ".plist")
}

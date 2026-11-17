import Foundation

/// The identity of one menu bar icon, stable across launches.
///
/// An icon belongs to an app (`bundleID`). Most apps own one icon, whose `key` is empty. Control Center's modules and
/// a few apps own several: they are told apart by their Accessibility identifier (`com.apple.menuextra.wifi`) when
/// they have one, otherwise by their rank among the app's icons, counted from the right (`#0`, `#1`). An icon's title
/// or description never enters its identity: Wi-Fi describes its signal and many apps show a live value.
public struct IconID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public var bundleID: String
    public var key: String

    public init(bundleID: String, key: String = "") {
        self.bundleID = bundleID
        self.key = key
    }

    public static func < (lhs: IconID, rhs: IconID) -> Bool {
        (lhs.bundleID, lhs.key) < (rhs.bundleID, rhs.key)
    }

    public var description: String { key.isEmpty ? bundleID : "\(bundleID)/\(key)" }
}

public enum IconIdentity {
    /// The identity of an icon as a scan sees it.
    /// - Parameters:
    ///   - identifier: the icon's Accessibility identifier, when the app gives one.
    ///   - indexFromRight: the icon's rank among its app's icons, 0 for the rightmost.
    ///   - countForApp: how many icons the app shows.
    public static func make(bundleID: String, identifier: String?, indexFromRight: Int, countForApp: Int) -> IconID {
        if let identifier, !identifier.trimmingCharacters(in: .whitespaces).isEmpty {
            return IconID(bundleID: bundleID, key: identifier)
        }
        return IconID(bundleID: bundleID, key: countForApp > 1 ? "#\(indexFromRight)" : "")
    }

    /// Accessibility identifiers of the icons macOS keeps at the right end of the menu bar: neither macOS 26 nor 27
    /// lets another app move or hide them.
    public static let fixedSystemIdentifiers: Set<String> = [
        "com.apple.menuextra.clock",
        "com.apple.menuextra.controlcenter",
    ]

    /// The icons Smart Sort leaves in the menu bar: the ones people glance at all day.
    public static let essentialSystemIdentifiers: Set<String> = fixedSystemIdentifiers.union([
        "com.apple.menuextra.battery",
        "com.apple.menuextra.wifi",
        "com.apple.menuextra.sound",
    ])
}

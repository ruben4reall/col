import Foundation

/// A keyboard shortcut: a virtual key code with its modifiers, and the key's label as recorded.
public struct Shortcut: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// A virtual key code (`kVK_*`), independent of the keyboard layout.
    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// What the key showed when the shortcut was recorded: "F", "Space", "→".
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// Modifiers in Apple's order, then the key: "⌃⌥⌘Space".
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyLabel
    }

    /// A shortcut needs a modifier other than Shift, or it would steal a key from every app.
    public var isUsable: Bool {
        !modifiers.subtracting(.shift).isEmpty
    }

    /// Search: ⌃⌥⌘Space (⌥⌘Space belongs to Finder, ⌃⌥Space to the input sources).
    public static let defaultSearch = Shortcut(keyCode: 49, modifiers: [.control, .option, .command], keyLabel: "Space")
    /// Focus: ⌃⌥⌘F.
    public static let defaultFocus = Shortcut(keyCode: 3, modifiers: [.control, .option, .command], keyLabel: "F")
}

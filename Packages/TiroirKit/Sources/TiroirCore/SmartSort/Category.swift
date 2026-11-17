import Foundation

/// What an app is for, the basis of Smart Sort's drawers. The order is the order drawers take in the menu bar.
public enum CategoryID: String, Codable, Sendable, CaseIterable {
    case files
    case security
    case messages
    case ai
    case developer
    case media
    case devices
    case system
    case productivity
    case utilities
    case design
    case games
    case other

    /// An emoji for the category, for people who prefer emoji marks.
    public var emoji: String {
        switch self {
        case .files: "☁️"
        case .security: "🔒"
        case .messages: "💬"
        case .ai: "✨"
        case .developer: "🛠️"
        case .media: "🎧"
        case .devices: "🖥️"
        case .system: "⚙️"
        case .productivity: "🗓️"
        case .utilities: "🧰"
        case .design: "🎨"
        case .games: "🎮"
        case .other: "📦"
        }
    }

    /// The SF Symbol a Smart Sort drawer of this kind starts with, drawn like macOS's own menu bar icons.
    public var symbol: String {
        switch self {
        case .files: "cloud.fill"
        case .security: "lock.fill"
        case .messages: "bubble.left.and.bubble.right.fill"
        case .ai: "sparkles"
        case .developer: "hammer.fill"
        case .media: "headphones"
        case .devices: "display"
        case .system: "gearshape.fill"
        case .productivity: "calendar"
        case .utilities: "wrench.and.screwdriver.fill"
        case .design: "paintpalette.fill"
        case .games: "gamecontroller.fill"
        case .other: "shippingbox.fill"
        }
    }

    /// Position in the menu bar, left to right.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

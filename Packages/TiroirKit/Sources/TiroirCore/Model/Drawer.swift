import Foundation

/// What a drawer shows in the menu bar.
public enum DrawerMark: Codable, Hashable, Sendable {
    /// One emoji.
    case emoji(String)
    /// An SF Symbol, drawn as a template image like the system's own menu bar icons: the default.
    case symbol(String)
    /// Up to three characters, for people who prefer letters.
    case text(String)

    /// The longest text mark.
    public static let maximumTextLength = 3

    /// An emoji mark holds exactly one character (one grapheme cluster: 🛠️ and 👩‍💻 count as one), a symbol mark a
    /// non-empty name, a text mark one to three visible characters.
    public var isValid: Bool {
        switch self {
        case .emoji(let value):
            // Digits, # and * are emoji with a text presentation: they only count above the ASCII and Latin-1 range.
            return value.count == 1 && value.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C)
            }
        case .symbol(let name):
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.count <= Self.maximumTextLength
        }
    }

    /// The mark with its text trimmed to what the menu bar can show.
    public var normalized: DrawerMark {
        switch self {
        case .emoji(let value): return .emoji(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .symbol(let name): return .symbol(name.trimmingCharacters(in: .whitespaces))
        case .text(let value): return .text(String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength)))
        }
    }

    // A stable, readable encoding: {"emoji": "☁️"}, {"symbol": "cloud.fill"}, {"text": "Dev"}.
    private enum CodingKeys: String, CodingKey { case emoji, symbol, text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .emoji) {
            self = .emoji(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .symbol) {
            self = .symbol(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(value)
        } else {
            self = .fallback
        }
    }

    /// The mark of a drawer whose own mark was lost or invalid.
    public static let fallback = DrawerMark.symbol("shippingbox.fill")

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .emoji(let value): try container.encode(value, forKey: .emoji)
        case .symbol(let value): try container.encode(value, forKey: .symbol)
        case .text(let value): try container.encode(value, forKey: .text)
        }
    }
}

/// A named group of icons, shown in the menu bar as one mark. Opening it drops a glass panel with its icons.
public struct Drawer: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var mark: DrawerMark
    /// The Smart Sort category it was made for: new icons of that kind land here when the policy says so.
    public var category: CategoryID?
    /// Show the name next to the mark in the menu bar.
    public var showsName: Bool
    /// Show how many icons it holds.
    public var showsCount: Bool
    /// A shortcut that opens it.
    public var shortcut: Shortcut?

    /// The longest name.
    public static let maximumNameLength = 40

    public init(
        id: UUID = UUID(), name: String, mark: DrawerMark, category: CategoryID? = nil, showsName: Bool = false,
        showsCount: Bool = false, shortcut: Shortcut? = nil
    ) {
        self.id = id
        self.name = name
        self.mark = mark
        self.category = category
        self.showsName = showsName
        self.showsCount = showsCount
        self.shortcut = shortcut
    }

    private enum CodingKeys: String, CodingKey { case id, name, mark, category, showsName, showsCount, shortcut }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        mark = try container.decodeIfPresent(DrawerMark.self, forKey: .mark) ?? .fallback
        category = try? container.decodeIfPresent(CategoryID.self, forKey: .category)
        showsName = try container.decodeIfPresent(Bool.self, forKey: .showsName) ?? false
        showsCount = try container.decodeIfPresent(Bool.self, forKey: .showsCount) ?? false
        shortcut = try? container.decodeIfPresent(Shortcut.self, forKey: .shortcut)
    }

    /// Name trimmed and shortened, mark normalized; an invalid mark becomes the fallback box.
    public var clamped: Drawer {
        var copy = self
        copy.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNameLength))
        copy.mark = mark.normalized
        if !copy.mark.isValid { copy.mark = .fallback }
        return copy
    }
}

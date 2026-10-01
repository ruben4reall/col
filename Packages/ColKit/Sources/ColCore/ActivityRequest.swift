import Foundation

/// A live activity described by another program, through the command line, the local socket, a link or Shortcuts.
///
///     { "id": "build", "title": "Build", "subtitle": "12 of 40 files", "symbol": "hammer.fill",
///       "tint": "orange", "progress": 0.3, "priority": "standard", "ttl": 60 }
public struct ActivityRequest: Codable, Equatable, Sendable {
    public var id: String
    public var title: String?
    public var subtitle: String?
    /// SF Symbol shown on the left of the camera.
    public var symbol: String?
    /// A colour name (orange, green, blue, purple, pink, red, yellow, white) or a hex value such as #FF8800.
    public var tint: String?
    /// 0 to 1: shows a ring on the right of the camera.
    public var progress: Double?
    /// Short text on the right of the camera, when there is no progress.
    public var text: String?
    public var priority: String?
    /// Seconds before the activity leaves by itself.
    public var ttl: Double?

    public init(
        id: String, title: String? = nil, subtitle: String? = nil, symbol: String? = nil, tint: String? = nil,
        progress: Double? = nil, text: String? = nil, priority: String? = nil, ttl: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.progress = progress
        self.text = text
        self.priority = priority
        self.ttl = ttl
    }

    public enum Invalid: Error, Equatable {
        case missingID
        case idTooLong
    }

    /// Checks what a caller sent. Ids are namespaced so outside callers never replace Col's own activities.
    public func validated() throws -> ActivityRequest {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Invalid.missingID }
        guard trimmed.count <= 64 else { throw Invalid.idTooLong }
        var copy = self
        copy.id = trimmed
        copy.progress = progress.map { min(max($0, 0), 1) }
        copy.ttl = ttl.map { min(max($0, 1), 24 * 3600) }
        copy.title = title.map { String($0.prefix(80)) }
        copy.subtitle = subtitle.map { String($0.prefix(120)) }
        copy.text = text.map { String($0.prefix(24)) }
        return copy
    }

    /// The board key: requests live in their own namespace.
    public var boardID: String { "api." + id }

    public var resolvedTint: RGBA { tint.flatMap(ColorName.parse) ?? .white }

    public var resolvedPriority: ActivityPriority {
        switch priority?.lowercased() {
        case "ambient", "low": .ambient
        case "alert", "high": .alert
        default: .standard
        }
    }

    public func activity(now: Date) -> Activity {
        let tint = resolvedTint
        let leading: CompactItem = .symbol(symbol ?? "circle.hexagongrid.fill", tint: tint)
        let trailing: CompactItem? = if let progress {
            .ring(progress: progress, tint: tint)
        } else if let text, !text.isEmpty {
            .text(text, tint: tint)
        } else {
            nil
        }
        return Activity(
            id: boardID,
            priority: resolvedPriority,
            compact: CompactPresentation(leading: leading, trailing: trailing),
            expires: ttl.map { now.addingTimeInterval($0) },
            updated: now
        )
    }
}

public enum ColorName {
    public static func parse(_ value: String) -> RGBA? {
        let name = value.trimmingCharacters(in: .whitespaces).lowercased()
        switch name {
        case "white": return .white
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink": return RGBA(red: 1, green: 0.22, blue: 0.47)
        case "teal": return RGBA(red: 0.19, green: 0.78, blue: 0.82)
        case "gray", "grey": return RGBA(red: 0.56, green: 0.56, blue: 0.58)
        default: break
        }
        var hex = name.hasPrefix("#") ? String(name.dropFirst()) : name
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { return nil }
        return RGBA(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}

import Foundation

/// A widget another program puts in the island: through `colctl widget set`, the local socket, Col Connect, an
/// extension, or a URL Col reads. One format for all of them, documented in docs/widgets.md.
///
///     { "id": "living-room", "title": "Living room", "value": 21.5, "unit": "°C", "symbol": "thermometer.medium",
///       "tint": "orange", "progress": 0.4, "lines": ["Humidity 48%"], "staleAfter": 900,
///       "buttons": [{"title": "Heat", "url": "http://homeassistant.local:8123/api/webhook/heat"}] }
public struct WidgetRequest: Codable, Equatable, Sendable {
    /// Letters, digits, dots, dashes and underscores, 64 at most. The path of `PUT /v1/widgets/<id>` gives it when
    /// the body does not.
    public var id: String
    public var title: String?
    /// The figure, as text. A number in the JSON is written the way people read it: 21.5, 3, 1200.
    public var value: String?
    /// Shown after the value, smaller: °C, %, runs.
    public var unit: String?
    /// 0 to 1: a bar under the value.
    public var progress: Double?
    /// An SF Symbol, beside the title.
    public var symbol: String?
    /// A colour name or #RRGGBB, as for activities.
    public var tint: String?
    /// Up to three short lines under the value.
    public var lines: [String]?
    /// Up to three buttons, each calling back an address.
    public var buttons: [WidgetButton]?
    /// Seconds after which the widget's figures are old: it dims and says when it was last updated.
    public var staleAfter: Double?
    /// Also show the widget in the closed island, beside the camera, as a live activity.
    public var activity: Bool?

    public init(
        id: String, title: String? = nil, value: String? = nil, unit: String? = nil, progress: Double? = nil,
        symbol: String? = nil, tint: String? = nil, lines: [String]? = nil, buttons: [WidgetButton]? = nil,
        staleAfter: Double? = nil, activity: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.unit = unit
        self.progress = progress
        self.symbol = symbol
        self.tint = tint
        self.lines = lines
        self.buttons = buttons
        self.staleAfter = staleAfter
        self.activity = activity
    }

    enum CodingKeys: String, CodingKey {
        case id, title, value, unit, progress, symbol, tint, lines, buttons, staleAfter, activity
        case staleAfterSnake = "stale_after"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
        value = try container.decodeIfPresent(JSONValue.self, forKey: .value).flatMap(Self.text)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        tint = try container.decodeIfPresent(String.self, forKey: .tint)
        lines = try container.decodeIfPresent([JSONValue].self, forKey: .lines)?.compactMap(Self.text)
        buttons = try container.decodeIfPresent([WidgetButton].self, forKey: .buttons)
        staleAfter = try container.decodeIfPresent(Double.self, forKey: .staleAfter)
            ?? container.decodeIfPresent(Double.self, forKey: .staleAfterSnake)
        activity = try container.decodeIfPresent(Bool.self, forKey: .activity)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(symbol, forKey: .symbol)
        try container.encodeIfPresent(tint, forKey: .tint)
        try container.encodeIfPresent(lines, forKey: .lines)
        try container.encodeIfPresent(buttons, forKey: .buttons)
        try container.encodeIfPresent(staleAfter, forKey: .staleAfter)
        try container.encodeIfPresent(activity, forKey: .activity)
    }

    /// A value as the widget shows it: text as it is, a number written plainly, true and false as words.
    public static func text(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): text
        case .number(let number): format(number)
        case .bool(let flag): flag ? "true" : "false"
        case .null, .array, .object: nil
        }
    }

    /// 21.5, 3, 1200, 0.33: no exponent, no trailing zeros, two decimals at most.
    public static func format(_ number: Double) -> String {
        guard number.isFinite else { return "–" }
        if number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
        var text = String(format: "%.2f", number)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    public enum Invalid: Error, Equatable, Sendable {
        case missingID
        case badID
        /// The button at this index has no title, or an address that is not http or https.
        case badButton(Int)
        case tooManyButtons

        /// What the API answers, so the sender knows what to fix.
        public var message: String {
            switch self {
            case .missingID: "a widget needs an id"
            case .badID: "a widget id is 1 to 64 letters, digits, dots, dashes or underscores"
            case .badButton(let index): "button \(index + 1) needs a title and an http or https url"
            case .tooManyButtons: "a widget has three buttons at most"
            }
        }
    }

    public static let maximumLines = 3
    public static let maximumButtons = 3
    /// From ten seconds to a week.
    public static let staleRange: ClosedRange<Double> = 10...604_800

    /// Whether a string can name a widget: it goes in addresses, so only characters that need no escaping.
    public static func isValidID(_ id: String) -> Bool {
        (1...64).contains(id.count) && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || "._-".unicodeScalars.contains($0)
        }
    }

    /// Checks what a sender gave: the id and the buttons must be right, the rest is trimmed to what the island shows.
    public func validated() throws -> WidgetRequest {
        var copy = self
        copy.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.id.isEmpty else { throw Invalid.missingID }
        guard Self.isValidID(copy.id) else { throw Invalid.badID }
        func clean(_ text: String?, _ limit: Int) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return String(text.prefix(limit))
        }
        copy.title = clean(title, 60)
        copy.value = clean(value, 32)
        copy.unit = clean(unit, 16)
        copy.symbol = clean(symbol, 80)
        copy.tint = clean(tint, 16).flatMap { ColorName.parse($0) == nil ? nil : $0 }
        copy.progress = progress.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
        let kept = (lines ?? []).compactMap { clean($0, 80) }.prefix(Self.maximumLines)
        copy.lines = kept.isEmpty ? nil : Array(kept)
        if let buttons, !buttons.isEmpty {
            guard buttons.count <= Self.maximumButtons else { throw Invalid.tooManyButtons }
            copy.buttons = try buttons.enumerated().map { index, button in
                guard let valid = button.validated() else { throw Invalid.badButton(index) }
                return valid
            }
        } else {
            copy.buttons = nil
        }
        copy.staleAfter = staleAfter.flatMap { $0.isFinite ? min(max($0, Self.staleRange.lowerBound), Self.staleRange.upperBound) : nil }
        return copy
    }

    public var resolvedTint: RGBA { tint.flatMap(ColorName.parse) ?? .white }

    /// The value and its unit, as the closed island's wing shows them.
    public var shownValue: String? {
        guard let value else { return nil }
        guard let unit else { return value }
        return unit.count <= 2 && !unit.first!.isLetter ? value + unit : "\(value) \(unit)"
    }

    /// Whether the figures are older than the sender said they stay true.
    public func isStale(updated: Date, now: Date) -> Bool {
        guard let staleAfter else { return false }
        return now.timeIntervalSince(updated) > staleAfter
    }

    /// The board key of the widget's activity in the closed island.
    public var activityID: String { "widget." + id }

    /// The widget in the closed island: its symbol on the left of the camera, its progress or value on the right. It
    /// leaves when its figures go stale.
    public func activity(updated: Date) -> Activity {
        let tint = resolvedTint
        let trailing: CompactItem? = if let progress {
            .ring(progress: progress, tint: tint)
        } else if let shown = shownValue {
            .text(String(shown.prefix(24)), tint: tint)
        } else {
            nil
        }
        return Activity(
            id: activityID,
            priority: .standard,
            compact: CompactPresentation(leading: .symbol(symbol ?? "square.grid.2x2.fill", tint: tint), trailing: trailing),
            expires: staleAfter.map { updated.addingTimeInterval($0) },
            updated: updated
        )
    }
}

/// A button of a widget: pressing it calls an address, once the user has said yes to that address.
public struct WidgetButton: Codable, Equatable, Hashable, Sendable {
    public var title: String
    public var url: String
    /// GET or POST; POST when not given, as webhooks expect.
    public var method: String?
    public var symbol: String?

    public init(title: String, url: String, method: String? = nil, symbol: String? = nil) {
        self.title = title
        self.url = url
        self.method = method
        self.symbol = symbol
    }

    public var resolvedMethod: String { method?.uppercased() == "GET" ? "GET" : "POST" }

    /// The button with a title and an http or https address with a host; nil when it has neither.
    public func validated() -> WidgetButton? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, url.count <= 2048, Self.isCallable(url) else { return nil }
        if let method, !["GET", "POST"].contains(method.uppercased()) { return nil }
        return WidgetButton(title: String(title.prefix(24)), url: url, method: resolvedMethod, symbol: symbol.map { String($0.prefix(80)) })
    }

    /// Only the web: http or https, with a host. Never a file, a script or another app's scheme.
    public static func isCallable(_ address: String) -> Bool {
        guard let components = URLComponents(string: address), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty
        else { return false }
        return true
    }

    /// What the user says yes to, once: the method and the whole address.
    public var confirmationKey: String { resolvedMethod + " " + url }
}

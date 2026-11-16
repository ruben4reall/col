import Foundation

/// A place in a JSON document, written the way people read it: `data.temp`, `items.0.name` or `items[0].name`.
public struct JSONKeyPath: Equatable, Sendable {
    public enum Component: Equatable, Sendable {
        case key(String)
        case index(Int)
    }

    public let components: [Component]

    /// Nil for an empty path, or one with an unclosed bracket.
    public init?(_ text: String) {
        var components: [Component] = []
        var current = ""
        var index = text.startIndex
        func flush() {
            guard !current.isEmpty else { return }
            components.append(Int(current).map { $0 >= 0 ? .index($0) : .key(current) } ?? .key(current))
            current = ""
        }
        while index < text.endIndex {
            let character = text[index]
            switch character {
            case ".":
                flush()
            case "[":
                flush()
                guard let close = text[index...].firstIndex(of: "]") else { return nil }
                let inside = text[text.index(after: index)..<close].trimmingCharacters(in: .whitespaces)
                let unquoted = inside.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let number = Int(inside), number >= 0 {
                    components.append(.index(number))
                } else if !unquoted.isEmpty {
                    components.append(.key(unquoted))
                }
                index = close
            default:
                current.append(character)
            }
            index = text.index(after: index)
        }
        flush()
        guard !components.isEmpty else { return nil }
        self.components = components
    }

    /// The value at this place, or nil when the document has nothing there. A number reaches into an array, or into
    /// an object that uses it as a key.
    public func value(in document: JSONValue) -> JSONValue? {
        var current = document
        for component in components {
            switch (component, current) {
            case (.key(let key), .object(let object)):
                guard let next = object[key] else { return nil }
                current = next
            case (.index(let index), .array(let array)):
                guard array.indices.contains(index) else { return nil }
                current = array[index]
            case (.index(let index), .object(let object)):
                guard let next = object[String(index)] else { return nil }
                current = next
            default:
                return nil
            }
        }
        return current
    }
}

/// Text with key paths in braces, filled from a JSON document: `{main.temp}°` gives `21.5°`. `{{` and `}}` write a
/// brace.
public enum WidgetTemplate {
    public struct Rendered: Equatable, Sendable {
        public var text: String
        /// The paths that led nowhere in the document, to say so in the settings' preview.
        public var missing: [String]
    }

    public static func render(_ template: String, in document: JSONValue) -> Rendered {
        var text = ""
        var missing: [String] = []
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            let next = template.index(after: index)
            if character == "{", next < template.endIndex, template[next] == "{" {
                text.append("{")
                index = template.index(after: next)
                continue
            }
            if character == "}", next < template.endIndex, template[next] == "}" {
                text.append("}")
                index = template.index(after: next)
                continue
            }
            if character == "{", let close = template[next...].firstIndex(of: "}") {
                let path = template[next..<close].trimmingCharacters(in: .whitespaces)
                if let keyPath = JSONKeyPath(path), let value = keyPath.value(in: document), let shown = WidgetRequest.text(value) {
                    text += shown
                } else {
                    missing.append(path)
                    text += "–"
                }
                index = template.index(after: close)
                continue
            }
            text.append(character)
            index = next
        }
        return Rendered(text: text, missing: missing)
    }

    /// Whether a template reads the document at all, rather than being plain text.
    public static func readsDocument(_ template: String) -> Bool {
        template.replacingOccurrences(of: "{{", with: "").contains("{")
    }
}

/// A widget read from an address: Col asks it for JSON at the interval the user chose, only while the widget shows,
/// and fills the widget from it. The answer can be in Col's widget format already, or any JSON read through templates.
public struct APIWidget: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var url: String
    /// Minutes between two reads, one at least.
    public var minutes: Int
    /// The names of the headers sent with each read; their values live in the Keychain.
    public var headers: [String]
    public var mapping: Mapping

    public init(id: String = "url-" + UUID().uuidString.prefix(8).lowercased(), name: String, url: String, minutes: Int = 15,
                headers: [String] = [], mapping: Mapping = Mapping()) {
        self.id = id
        self.name = name
        self.url = url
        self.minutes = minutes
        self.headers = headers
        self.mapping = mapping
    }

    /// Each field of the widget, as plain text or a template such as `{data.temp}`. Empty fields are left out; with
    /// every field empty, the answer is read as a widget in Col's own format.
    public struct Mapping: Codable, Equatable, Hashable, Sendable {
        public var title: String
        public var value: String
        public var unit: String
        /// A number, or a template giving one.
        public var progress: String
        /// What the progress counts up to: 100 for a percentage. Without it, a number above 1 is read as a percentage.
        public var progressMaximum: Double?
        public var symbol: String
        public var tint: String
        public var lines: [String]

        public init(title: String = "", value: String = "", unit: String = "", progress: String = "", progressMaximum: Double? = nil,
                    symbol: String = "", tint: String = "", lines: [String] = []) {
            self.title = title
            self.value = value
            self.unit = unit
            self.progress = progress
            self.progressMaximum = progressMaximum
            self.symbol = symbol
            self.tint = tint
            self.lines = lines
        }

        /// No field filled: the answer is a widget in Col's format.
        public var isEmpty: Bool {
            [title, value, unit, progress, symbol, tint].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
                && lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    public static let minimumMinutes = 1

    /// Seconds between two reads.
    public var interval: TimeInterval { TimeInterval(max(minutes, Self.minimumMinutes) * 60) }

    public enum Invalid: Error, Equatable, Sendable {
        case badURL
        case notJSON
        case badWidget(WidgetRequest.Invalid)
    }

    /// Only http and https, with a host.
    public var isValidURL: Bool { WidgetButton.isCallable(url) }

    /// A header name as HTTP allows it: letters, digits and dashes.
    public static func isValidHeaderName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }
    }

    /// The widget an answer gives, and the key paths that led nowhere in it.
    public func widget(from data: Data) throws -> (widget: WidgetRequest, missing: [String]) {
        guard let document = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw Invalid.notJSON }
        return try widget(from: document)
    }

    public func widget(from document: JSONValue) throws -> (widget: WidgetRequest, missing: [String]) {
        if mapping.isEmpty {
            // Col's own format: the address answers a widget, whose id is this one's.
            guard case .object = document,
                  let data = try? JSONEncoder().encode(document),
                  var widget = try? JSONDecoder().decode(WidgetRequest.self, from: data)
            else { throw Invalid.notJSON }
            widget.id = id
            if widget.title == nil { widget.title = name }
            do { return (try widget.validated(), []) } catch let error as WidgetRequest.Invalid { throw Invalid.badWidget(error) }
        }
        var missing: [String] = []
        func field(_ template: String) -> String? {
            guard !template.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let rendered = WidgetTemplate.render(template, in: document)
            missing += rendered.missing
            return rendered.text
        }
        let progress = field(mapping.progress).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { number in
            if let maximum = mapping.progressMaximum, maximum > 0 { return number / maximum }
            return number > 1 ? number / 100 : number
        }
        let lines = mapping.lines.compactMap(field)
        var widget = WidgetRequest(
            id: id, title: field(mapping.title) ?? name, value: field(mapping.value), unit: field(mapping.unit),
            progress: progress, symbol: field(mapping.symbol), tint: field(mapping.tint), lines: lines.isEmpty ? nil : lines,
            // Read on a schedule: the figures are old once two reads have been missed.
            staleAfter: interval * 2 + 30
        )
        do { widget = try widget.validated() } catch let error as WidgetRequest.Invalid { throw Invalid.badWidget(error) }
        return (widget, missing)
    }
}

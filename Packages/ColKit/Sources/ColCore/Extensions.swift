import Foundation

/// An extension: a folder with an `extension.json` and a script that Col runs on a schedule.
///
///     { "name": "GitHub Actions", "command": "./status.sh", "interval": 60 }
///
/// The script prints a JSON activity on stdout (the fields of `colctl push`, without the id), or nothing to clear its
/// activity. It can also call `colctl push` itself.
public struct ExtensionManifest: Codable, Equatable, Sendable {
    public var name: String
    public var command: String
    /// Seconds between runs; at least 10, at most a day.
    public var interval: Double
    public var description: String?

    public init(name: String, command: String, interval: Double, description: String? = nil) {
        self.name = name
        self.command = command
        self.interval = interval
        self.description = description
    }

    public enum Invalid: Error, Equatable {
        case missingName
        case missingCommand
    }

    public func validated() throws -> ExtensionManifest {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.name.isEmpty else { throw Invalid.missingName }
        guard !copy.command.isEmpty else { throw Invalid.missingCommand }
        copy.interval = min(max(interval, 10), 86_400)
        return copy
    }

    /// What one run printed: an activity for the extension, or nothing, which clears it. A run that prints only a
    /// `widget` gives no activity.
    public static func activity(fromOutput output: Data, folder: String) -> ActivityRequest? {
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return nil }
        if object["widget"] != nil {
            object["widget"] = nil
            guard !object.isEmpty else { return nil }
        }
        object["id"] = "ext-" + folder
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let request = try? JSONDecoder().decode(ActivityRequest.self, from: data)
        else { return nil }
        return try? request.validated()
    }

    /// The widget a run printed under `widget`, in the format of docs/widgets.md, as the extension's widget
    /// (`ext-<folder>`); nil when it printed none, or one that is not valid.
    ///
    ///     {"widget": {"title": "Homebrew", "value": 3, "unit": "outdated", "symbol": "mug.fill"}}
    public static func widget(fromOutput output: Data, folder: String) -> WidgetRequest? {
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let object = (try? JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))),
              case .object(var fields)? = object["widget"]
        else { return nil }
        fields["id"] = .string(widgetID(folder: folder))
        guard let data = try? JSONEncoder().encode(fields),
              let widget = try? JSONDecoder().decode(WidgetRequest.self, from: data)
        else { return nil }
        return try? widget.validated()
    }

    /// The id of an extension's widget: its folder's name, kept to the characters a widget id allows.
    public static func widgetID(folder: String) -> String {
        let kept = folder.unicodeScalars.map { scalar -> Character in
            WidgetRequest.isValidID(String(scalar)) ? Character(scalar) : "-"
        }
        return String(("ext-" + String(kept)).prefix(64))
    }
}

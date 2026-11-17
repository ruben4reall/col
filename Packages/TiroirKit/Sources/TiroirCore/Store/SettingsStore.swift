import Foundation

/// Reads and writes Tiroir's settings as one JSON value in the preferences (key `settings`).
public final class SettingsStore: @unchecked Sendable {
    /// What `load()` found.
    public enum Outcome: Equatable, Sendable {
        /// Nothing stored yet: the defaults.
        case fresh
        /// The stored settings, clamped to their ranges.
        case loaded
        /// The stored value could not be read: the defaults, and the value is left untouched until the next save.
        case unreadable
        /// The settings come from a newer Tiroir: the defaults, and the value is left untouched until the next save.
        case newerVersion(Int)
    }

    // UserDefaults is thread-safe; the store adds no state of its own.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> (settings: TiroirSettings, outcome: Outcome) {
        guard let data = defaults.data(forKey: key) else { return (.defaults, .fresh) }
        switch Self.read(data) {
        case .success(let settings): return (settings, .loaded)
        case .failure(.newerVersion(let version)): return (.defaults, .newerVersion(version))
        case .failure(.unreadable): return (.defaults, .unreadable)
        }
    }

    public func save(_ settings: TiroirSettings) {
        guard let data = Self.data(settings) else { return }
        defaults.set(data, forKey: key)
    }

    /// Why a settings file cannot be used.
    public enum ReadError: Error, Equatable, Sendable {
        case unreadable
        case newerVersion(Int)
    }

    /// Settings from JSON (a saved value or an exported file), clamped to their ranges.
    public static func read(_ data: Data) -> Result<TiroirSettings, ReadError> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.unreadable) }
        if let version = object["schemaVersion"] as? Int, version > TiroirSettings.currentSchemaVersion {
            return .failure(.newerVersion(version))
        }
        guard let settings = try? JSONDecoder().decode(TiroirSettings.self, from: data) else { return .failure(.unreadable) }
        return .success(settings.clamped)
    }

    /// Settings as JSON, keys sorted; `pretty` for a file people may read.
    public static func data(_ settings: TiroirSettings, pretty: Bool = false) -> Data? {
        var stored = settings.clamped
        stored.schemaVersion = TiroirSettings.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys]
        return try? encoder.encode(stored)
    }

    /// Forgets everything: the next launch starts with the welcome.
    public func reset() {
        defaults.removeObject(forKey: key)
    }
}

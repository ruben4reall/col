import Foundation

/// The curated list of menu bar apps and what they are for (`Resources/Catalog.json`), edited by pull request.
public struct Catalog: Sendable {
    public struct KeywordRule: Codable, Sendable, Equatable {
        public var words: [String]
        public var category: CategoryID
    }

    /// Exact bundle identifiers.
    public var apps: [String: CategoryID]
    /// Bundle identifier prefixes, for vendors whose every menu bar app has the same purpose.
    public var prefixes: [String: CategoryID]
    /// App Store categories (`LSApplicationCategoryType`), the last resort before Other.
    public var appStoreCategories: [String: CategoryID]
    /// Whole words in an app's name or bundle identifier.
    public var keywords: [KeywordRule]

    public init(
        apps: [String: CategoryID] = [:], prefixes: [String: CategoryID] = [:],
        appStoreCategories: [String: CategoryID] = [:], keywords: [KeywordRule] = []
    ) {
        self.apps = apps
        self.prefixes = prefixes
        self.appStoreCategories = appStoreCategories
        self.keywords = keywords
    }

    /// The catalog shipped with Tiroir. An unreadable file would be a build error, caught by the tests; at run time it
    /// degrades to an empty catalog, and Smart Sort falls back to keywords and App Store categories.
    public static let shipped: Catalog = {
        guard let url = Bundle.module.url(forResource: "Catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? Catalog.decode(data) else { return Catalog() }
        return catalog
    }()

    private struct File: Decodable {
        var version: Int
        var apps: [String: String]
        var prefixes: [String: String]
        var appStoreCategories: [String: String]
        var keywords: [RawRule]
        struct RawRule: Decodable { var words: [String]; var category: String }
    }

    public enum DecodingProblem: Error, Equatable {
        case unknownCategory(String)
    }

    /// Reads a catalog file. Every category it names must exist, so a typo fails the tests instead of sorting apps
    /// into Other.
    public static func decode(_ data: Data) throws -> Catalog {
        let file = try JSONDecoder().decode(File.self, from: data)
        func category(_ raw: String) throws -> CategoryID {
            guard let value = CategoryID(rawValue: raw) else { throw DecodingProblem.unknownCategory(raw) }
            return value
        }
        return Catalog(
            apps: try file.apps.mapValues(category),
            prefixes: try file.prefixes.mapValues(category),
            appStoreCategories: try file.appStoreCategories.mapValues(category),
            keywords: try file.keywords.map { KeywordRule(words: $0.words.map { $0.lowercased() }, category: try category($0.category)) }
        )
    }
}

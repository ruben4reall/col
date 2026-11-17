import Foundation

/// One entry search can find: an icon, with the words people may type to reach it.
public struct SearchItem: Equatable, Sendable {
    public var id: IconID
    /// The app's name, or the module's label for macOS icons: "Google Drive", "Battery".
    public var title: String
    /// The icon's own label when it differs from the title.
    public var subtitle: String?
    /// The drawer it lives in, if any.
    public var drawerName: String?

    public init(id: IconID, title: String, subtitle: String? = nil, drawerName: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.drawerName = drawerName
    }
}

/// Ranks icons for the search field. Case and accents never matter; a word that starts with what was typed beats a
/// match inside a word; the order of equal matches is the menu bar's.
public enum SearchRanker {
    public static func rank(_ query: String, in items: [SearchItem]) -> [SearchItem] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item -> (item: SearchItem, score: Int, offset: Int)? in
                let score = self.score(needle, item)
                return score > 0 ? (item, score, offset) : nil
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .map(\.item)
    }

    static func score(_ needle: String, _ item: SearchItem) -> Int {
        let title = normalize(item.title)
        let titleWords = words(title)
        var best = 0
        if title == needle { best = max(best, 1000) }
        if title.hasPrefix(needle) { best = max(best, 800) }
        if titleWords.contains(where: { $0.hasPrefix(needle) }) { best = max(best, 600) }
        if initials(titleWords).hasPrefix(needle), needle.count >= 2 { best = max(best, 500) }
        if let subtitle = item.subtitle.map(normalize), words(subtitle).contains(where: { $0.hasPrefix(needle) }) {
            best = max(best, 400)
        }
        if let drawer = item.drawerName.map(normalize), words(drawer).contains(where: { $0.hasPrefix(needle) }) {
            best = max(best, 300)
        }
        if needle.count >= 2, title.contains(needle) { best = max(best, 100) }
        return best
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func initials(_ words: [String]) -> String {
        String(words.compactMap(\.first))
    }
}

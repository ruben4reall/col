import Foundation

/// Decides what an app is for (spec 5). First match wins:
/// 1. the person's own choice for that app;
/// 2. the catalog's exact bundle identifier, then its longest matching prefix;
/// 3. a whole-word keyword in the app's name or bundle identifier;
/// 4. the App Store category the app declares (last, because many declare the wrong one);
/// 5. Other.
public struct Classifier: Sendable {
    public var catalog: Catalog

    public init(catalog: Catalog = .shipped) {
        self.catalog = catalog
    }

    public func classify(
        bundleID: String, name: String, appStoreCategory: String? = nil, userChoice: CategoryID? = nil
    ) -> CategoryID {
        if let userChoice { return userChoice }
        if let exact = catalog.apps[bundleID] { return exact }
        if let prefixed = catalog.prefixes
            .filter({ bundleID.hasPrefix($0.key) })
            .max(by: { $0.key.count < $1.key.count })?.value {
            return prefixed
        }
        let words = Self.words(in: name).union(Self.words(in: bundleID))
        for rule in catalog.keywords where rule.words.contains(where: words.contains) {
            return rule.category
        }
        if let appStoreCategory {
            let normalized = appStoreCategory.lowercased()
            if let declared = catalog.appStoreCategories[normalized] { return declared }
            // Every game genre ("public.app-category.puzzle-games") is a game.
            if normalized.hasSuffix("-games") { return .games }
        }
        return .other
    }

    /// The whole words of a name or a bundle identifier, lowercased: "NordVPN" gives nord, vpn and nordvpn;
    /// "com.protonmail.bridge" gives com, protonmail, bridge. A keyword never matches inside a word ("Mailbox" is not
    /// "mail").
    static func words(in text: String) -> Set<String> {
        var result = Set<String>()
        for chunk in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let piece = String(chunk)
            result.insert(piece.lowercased())
            for part in splitCamelCase(piece) { result.insert(part.lowercased()) }
        }
        return result
    }

    /// "NordVPN" → ["Nord", "VPN"]; "iStatMenus" → ["i", "Stat", "Menus"]; "LMStudio" → ["LM", "Studio"].
    static func splitCamelCase(_ word: String) -> [String] {
        let characters = Array(word)
        guard characters.count > 1 else { return [word] }
        var parts: [String] = []
        var current = String(characters[0])
        for index in 1..<characters.count {
            let previous = characters[index - 1]
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let startsWord = (character.isUppercase && previous.isLowercase)
                || (character.isUppercase && previous.isUppercase && (next?.isLowercase ?? false))
                || (character.isNumber != previous.isNumber)
            if startsWord {
                parts.append(current)
                current = ""
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }
}

import Foundation

/// Which regional variants of a language to try for on-device speech recognition, best first: the locale asked for,
/// the reader's own region, the language's usual region, then the others. A Mac whose only English model is American
/// still follows an English script when the Mac is set to Switzerland.
public enum RecognitionLocales {
    public static func candidates(for locale: Locale, supported: [Locale], current: Locale) -> [Locale] {
        let language = locale.language.languageCode?.identifier
        let sameLanguage = supported.filter { $0.language.languageCode?.identifier == language }
        let usualRegion = language.flatMap { Locale.Language(identifier: $0).maximalIdentifier.split(separator: "-").last.map(String.init) }
        func rank(_ candidate: Locale) -> Int {
            let region = candidate.region?.identifier
            if region != nil, region == current.region?.identifier { return 0 }
            if region != nil, region == usualRegion { return 1 }
            return 2
        }
        let ordered = sameLanguage.sorted {
            let (left, right) = (rank($0), rank($1))
            return left != right ? left < right : ($0.region?.identifier ?? "") < ($1.region?.identifier ?? "")
        }
        var seen = Set<String>()
        return ([locale] + ordered).filter { seen.insert(key($0)).inserted }
    }

    private static func key(_ locale: Locale) -> String {
        [locale.language.languageCode?.identifier, locale.region?.identifier].compactMap { $0 }.joined(separator: "_")
    }
}

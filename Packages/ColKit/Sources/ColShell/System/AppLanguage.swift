import AppKit

/// The language Col speaks. By default the Mac's: macOS picks, among the languages Col has, the first one the user
/// prefers. A choice made in the settings is kept in Col's own defaults and applies from the next launch.
@MainActor
enum AppLanguage {
    private static let key = "AppleLanguages"

    /// The languages Col is translated into, as identifiers ("en", "fr").
    static var available: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }.sorted { name(for: $0) < name(for: $1) }
    }

    /// The language chosen in the settings, or nil to follow the Mac.
    static var chosen: String? {
        guard let identifier = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: identifier)?[key] as? [String]
        else { return nil }
        return languages.first
    }

    /// The language Col is showing now.
    static var current: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// The language the Mac would give Col, ignoring any choice made here.
    static var system: String {
        Bundle.preferredLocalizations(from: Bundle.main.localizations.filter { $0 != "Base" }, forPreferences: macLanguages).first ?? "en"
    }

    /// The Mac's first language, even one Col is not translated into ("de-CH").
    static var mac: String {
        macLanguages.first ?? current
    }

    /// The Mac's languages, from its global settings: Col's own choice, kept in its defaults, would come first in
    /// `Locale.preferredLanguages`.
    private static var macLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String] ?? Locale.preferredLanguages
    }

    /// Where the language Col speaks comes from: a choice made in Col, the Mac's own, or the closest one Col has when
    /// it does not speak the Mac's yet.
    enum Origin: Equatable {
        case chosen, mac, untranslated(mac: String)
    }

    nonisolated static func origin(current: String, chosen: String?, mac: String) -> Origin {
        if chosen != nil { return .chosen }
        return languageCode(current) == languageCode(mac) ? .mac : .untranslated(mac: languageCode(mac))
    }

    /// The language alone, without its region or script: "de" for "de-CH", "zh" for "zh-Hans-CN".
    nonisolated static func languageCode(_ identifier: String) -> String {
        Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
    }

    /// A language's name in itself: "English", "Français", "日本語".
    static func name(for identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        let name = locale.localizedString(forIdentifier: identifier) ?? identifier
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Keeps the choice for the next launch; nil follows the Mac again.
    static func choose(_ identifier: String?) {
        if let identifier {
            UserDefaults.standard.set([identifier], forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Quits and opens Col again, in the language now chosen.
    static func relaunch(at bundle: URL = Bundle.main.bundleURL) {
        let path = bundle.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The new Col starts once this one is gone: two would mean two islands on one notch.
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$0\"",
                             path, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        NSApp.terminate(nil)
    }
}

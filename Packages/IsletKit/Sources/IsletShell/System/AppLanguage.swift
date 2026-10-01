import AppKit

/// The language Islet speaks. By default the Mac's: macOS picks, among the languages Islet has, the first one the user
/// prefers. A choice made in the settings is kept in Islet's own defaults and applies from the next launch.
@MainActor
enum AppLanguage {
    private static let key = "AppleLanguages"

    /// The languages Islet is translated into, as identifiers ("en", "fr").
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

    /// The language Islet is showing now.
    static var current: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// The language the Mac would give Islet, ignoring any choice made here.
    static var system: String {
        let preferred = (UserDefaults(suiteName: UserDefaults.globalDomain)?.stringArray(forKey: key) ?? Locale.preferredLanguages)
        return Bundle.preferredLocalizations(from: Bundle.main.localizations.filter { $0 != "Base" }, forPreferences: preferred).first ?? "en"
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

    /// Quits and opens Islet again, in the language now chosen.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The new Islet starts once this one is gone: two would mean two islands on one notch.
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$0\"",
                             path, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        NSApp.terminate(nil)
    }
}

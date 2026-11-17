import Foundation

/// Who makes an app, for Smart Sort by developer. The cleanest source is the organisation in the app's Developer ID
/// certificate ("Developer ID Application: Proton AG (2SB5Z68H26)" gives Proton). Apple signs its own apps and the
/// App Store's, so those fall back to known bundle prefixes, then to the app's name.
public enum DeveloperName {
    public static func from(certificateSummary: String?, bundleID: String, appName: String) -> String {
        if bundleID.hasPrefix("com.apple.") { return "Apple" }
        if let summary = certificateSummary?.trimmingCharacters(in: .whitespaces), !summary.isEmpty {
            if let organization = organization(inDeveloperID: summary) { return organization }
        }
        if let known = knownPrefixes.first(where: { bundleID.hasPrefix($0.prefix) }) { return known.name }
        let name = appName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? bundleID : name
    }

    /// "Developer ID Application: Orbital Labs, LLC (U.S.) (HUAQ24HBR6)" → "Orbital Labs".
    static func organization(inDeveloperID summary: String) -> String? {
        let marker = "Developer ID Application:"
        guard let range = summary.range(of: marker) else { return nil }
        var organization = summary[range.upperBound...].trimmingCharacters(in: .whitespaces)
        // The team identifier, then any other trailing parenthesis such as "(U.S.)".
        while organization.hasSuffix(")"), let open = organization.lastIndex(of: "(") {
            organization = organization[..<open].trimmingCharacters(in: .whitespaces)
        }
        var changed = true
        while changed {
            changed = false
            for suffix in legalSuffixes where organization.lowercased().hasSuffix(suffix) {
                organization = String(organization.dropLast(suffix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
                changed = true
            }
        }
        return organization.isEmpty ? nil : organization
    }

    /// Lowercased legal forms, longest first so ", inc." goes before "inc.".
    static let legalSuffixes: [String] = [
        " co., ltd.", " pty ltd", " pty. ltd.", " corporation", " limited", " gmbh", " s.a.r.l.", " sarl",
        " s.a.s.", " sas", " s.a.", " b.v.", " bv", " a.g.", " ag", " s.l.", " sl", " l.l.c.", " llc", " ltd.",
        " ltd", " inc.", " inc", " corp.", " corp", " ab", " oy", " as", " aps", " sa", " srl", " s.r.l.",
    ]

    /// Developers of App Store apps, which carry Apple's signature instead of theirs.
    static let knownPrefixes: [(prefix: String, name: String)] = [
        ("com.google.", "Google"),
        ("com.microsoft.", "Microsoft"),
        ("com.adobe.", "Adobe"),
        ("ch.protonmail.", "Proton"),
        ("com.protonmail.", "Proton"),
        ("me.proton.", "Proton"),
        ("ch.protonvpn.", "Proton"),
        ("com.nordvpn.", "NordVPN"),
        ("com.expressvpn.", "ExpressVPN"),
        ("com.1password.", "1Password"),
        ("com.agilebits.", "1Password"),
        ("com.rogueamoeba.", "Rogue Amoeba"),
        ("com.bjango.", "Bjango"),
        ("com.sindresorhus.", "Sindre Sorhus"),
        ("com.macpaw.", "MacPaw"),
        ("com.objective-see.", "Objective-See"),
        ("com.logi.", "Logitech"),
        ("com.logitech.", "Logitech"),
        ("com.elgato.", "Elgato"),
        ("com.rode.", "RØDE"),
        ("com.jetbrains.", "JetBrains"),
        ("com.anthropic.", "Anthropic"),
        ("com.openai.", "OpenAI"),
        ("com.spotify.", "Spotify"),
        ("com.getdropbox.", "Dropbox"),
        ("ch.rubencatalao.", "Ruben Catalao"),
    ]
}

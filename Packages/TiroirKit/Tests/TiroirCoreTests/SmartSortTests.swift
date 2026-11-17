import Foundation
import Testing
@testable import TiroirCore

@Suite struct CatalogTests {
    static let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/TiroirCore/Resources/Catalog.json")

    @Test func theShippedCatalogLoads() {
        #expect(Catalog.shipped.apps.count > 200)
        #expect(Catalog.shipped.apps["com.google.drivefs"] == .files)
        #expect(!Catalog.shipped.keywords.isEmpty)
    }

    @Test func everyCategoryNamedInTheFileExists() throws {
        let data = try Data(contentsOf: Self.file)
        #expect(throws: Never.self) { try Catalog.decode(data) }
    }

    @Test func aTypoInACategoryIsCaught() {
        let json = #"{"version": 1, "apps": {"a": "fils"}, "prefixes": {}, "appStoreCategories": {}, "keywords": []}"#
        #expect(throws: Catalog.DecodingProblem.unknownCategory("fils")) { try Catalog.decode(Data(json.utf8)) }
    }

    /// JSON keeps the last of two equal keys silently: each section must list a bundle identifier once.
    @Test func noBundleIdentifierIsListedTwice() throws {
        let text = try String(contentsOf: Self.file, encoding: .utf8)
        for section in ["apps", "prefixes"] {
            guard let start = text.range(of: "\"\(section)\": {"),
                  let end = text.range(of: "\n  }", range: start.upperBound..<text.endIndex) else {
                Issue.record("no \(section) section")
                continue
            }
            let block = String(text[start.upperBound..<end.lowerBound])
            let keys = block.matches(of: #/"([A-Za-z0-9._-]+)"\s*:/#).map { String($0.output.1) }
            #expect(!keys.isEmpty)
            let duplicates = Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
            #expect(duplicates.isEmpty, "listed twice in \(section): \(duplicates)")
        }
    }

    @Test func appStoreKeysAreLowercase() {
        for key in Catalog.shipped.appStoreCategories.keys {
            #expect(key == key.lowercased())
        }
    }
}

@Suite struct ClassifierTests {
    let classifier = Classifier()

    @Test func theCatalogKnowsCommonApps() {
        #expect(classifier.classify(bundleID: "com.google.drivefs", name: "Google Drive") == .files)
        #expect(classifier.classify(bundleID: "com.protonmail.bridge", name: "Proton Mail Bridge") == .files)
        #expect(classifier.classify(bundleID: "com.hnc.Discord", name: "Discord") == .messages)
        #expect(classifier.classify(bundleID: "dev.kdrag0n.MacVirt", name: "OrbStack") == .developer)
        #expect(classifier.classify(bundleID: "com.spotify.client", name: "Spotify") == .media)
    }

    /// Claude declares developer tools and NordVPN utilities: the catalog knows better.
    @Test func theCatalogBeatsWhatAppsDeclare() {
        #expect(classifier.classify(bundleID: "com.anthropic.claudefordesktop", name: "Claude",
                                    appStoreCategory: "public.app-category.developer-tools") == .ai)
        #expect(classifier.classify(bundleID: "com.nordvpn.NordVPN", name: "NordVPN",
                                    appStoreCategory: "public.app-category.utilities") == .security)
    }

    @Test func prefixesCoverAVendorsApps() {
        #expect(classifier.classify(bundleID: "com.adobe.somethingNew", name: "Adobe Thing") == .design)
        #expect(classifier.classify(bundleID: "ch.protonvpn.mac.beta", name: "Proton VPN Beta") == .security)
    }

    @Test func theLongestPrefixWins() {
        let catalog = Catalog(prefixes: ["com.example.": .utilities, "com.example.games.": .games])
        let classifier = Classifier(catalog: catalog)
        #expect(classifier.classify(bundleID: "com.example.games.chess", name: "Chess") == .games)
        #expect(classifier.classify(bundleID: "com.example.notes", name: "Notes") == .utilities)
    }

    @Test func keywordsMatchWholeWordsOnly() {
        #expect(classifier.classify(bundleID: "com.unknown.shield", name: "ShieldVPN") == .security)
        #expect(classifier.classify(bundleID: "org.someone.sync", name: "Folder Mirror") == .files)
        #expect(classifier.classify(bundleID: "com.unknown.mailboxer", name: "Mailboxer") == .other)
        #expect(classifier.classify(bundleID: "com.unknown.gmailify", name: "Gmailify") == .other)
    }

    @Test func theAppStoreCategoryComesLast() {
        #expect(classifier.classify(bundleID: "com.unknown.tool", name: "Toolbox",
                                    appStoreCategory: "public.app-category.developer-tools") == .developer)
        #expect(classifier.classify(bundleID: "com.unknown.chess", name: "Knights",
                                    appStoreCategory: "public.app-category.board-games") == .games)
        #expect(classifier.classify(bundleID: "com.unknown.x", name: "X",
                                    appStoreCategory: "PUBLIC.APP-CATEGORY.MUSIC") == .media)
    }

    @Test func thePersonsChoiceAlwaysWins() {
        #expect(classifier.classify(bundleID: "com.google.drivefs", name: "Google Drive", userChoice: .productivity) == .productivity)
    }

    @Test func unknownAppsGoToOther() {
        #expect(classifier.classify(bundleID: "com.unknown.thing", name: "Thing") == .other)
    }

    @Test func wordsSplitCamelCaseAndSeparators() {
        let words = Classifier.words(in: "com.nordvpn.NordVPN")
        #expect(words.isSuperset(of: ["nordvpn", "nord", "vpn", "com"]))
        #expect(Classifier.splitCamelCase("LMStudio") == ["LM", "Studio"])
        #expect(Classifier.splitCamelCase("iStatMenus") == ["i", "Stat", "Menus"])
        #expect(Classifier.splitCamelCase("Pro2Go") == ["Pro", "2", "Go"])
    }
}

@Suite struct DeveloperNameTests {
    @Test func developerIDCertificatesNameTheOrganisation() {
        func name(_ summary: String) -> String {
            DeveloperName.from(certificateSummary: summary, bundleID: "x.y", appName: "App")
        }
        #expect(name("Developer ID Application: Google LLC (EQHXZ8M8AV)") == "Google")
        #expect(name("Developer ID Application: Proton AG (2SB5Z68H26)") == "Proton")
        #expect(name("Developer ID Application: Discord, Inc. (53Q6R32WPB)") == "Discord")
        #expect(name("Developer ID Application: Orbital Labs, LLC (U.S.) (HUAQ24HBR6)") == "Orbital Labs")
        #expect(name("Developer ID Application: Mozilla Corporation (43AQ936H96)") == "Mozilla")
        #expect(name("Developer ID Application: Ruben Catalao (TEAMID1234)") == "Ruben Catalao")
    }

    @Test func applesOwnAppsAreApple() {
        #expect(DeveloperName.from(certificateSummary: "Software Signing", bundleID: "com.apple.Spotlight", appName: "Spotlight") == "Apple")
    }

    @Test func appStoreAppsFallBackToKnownPrefixesThenTheirName() {
        let nord = DeveloperName.from(certificateSummary: "Apple Mac OS Application Signing", bundleID: "com.nordvpn.NordVPN", appName: "NordVPN")
        #expect(nord == "NordVPN")
        let proton = DeveloperName.from(certificateSummary: nil, bundleID: "ch.protonmail.desktop", appName: "Proton Mail")
        #expect(proton == "Proton")
        let unknown = DeveloperName.from(certificateSummary: "Apple Mac OS Application Signing", bundleID: "com.unknown.x", appName: "Thing")
        #expect(unknown == "Thing")
    }
}

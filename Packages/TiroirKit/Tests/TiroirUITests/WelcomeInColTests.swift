import Foundation
import Testing
@testable import TiroirUI

/// Col asks for its one permission in its own welcome and settings: once granted, the drawers' welcome has no
/// permission step.
@MainActor
@Suite struct WelcomeInColTests {
    @Test func withThePermissionTheWelcomeGoesFromHelloToSmartSort() {
        let welcome = WelcomeModel(step: .hello)
        welcome.skipsPermission = true
        #expect(welcome.steps == [.hello, .sort, .ready])
        welcome.next()
        #expect(welcome.step == .sort)
        welcome.previous()
        #expect(welcome.step == .hello)
    }

    @Test func withoutItTheStepStays() {
        let welcome = WelcomeModel(step: .hello)
        #expect(welcome.steps == [.hello, .permission, .sort, .ready])
        welcome.next()
        #expect(welcome.step == .permission)
        welcome.next()
        welcome.next()
        #expect(welcome.step == .ready)
        welcome.next()
        #expect(welcome.step == .ready)
    }

    /// The drawers say Col, never the standalone app's name, in every language but French, where a drawer is a tiroir.
    @Test func noStringNamesTheStandaloneApp() throws {
        let strings = try StringCatalogTests.catalog()["strings"] as? [String: [String: Any]] ?? [:]
        for (key, entry) in strings {
            #expect(!key.contains("Tiroir"), "\(key)")
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for (language, unit) in localizations where language != "fr" {
                let value = (unit["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                #expect(!value.contains("Tiroir"), "\(language): \(value)")
            }
        }
    }
}

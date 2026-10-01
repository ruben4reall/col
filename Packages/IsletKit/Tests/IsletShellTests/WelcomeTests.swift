import IsletCore
import Testing
@testable import IsletShell

@MainActor
struct WelcomeTests {
    @Test func helloStartsAndEndsInTheMacsLanguage() {
        let french = GreetingView.sequence(for: "fr-CH")
        #expect(french.first == "Bonjour" && french.last == "Bonjour")
        #expect(french.count == 9)
        // Never the same word twice in a row, nor the Mac's own between first and last.
        #expect(!french.dropFirst().dropLast().contains("Bonjour"))
        #expect(zip(french, french.dropFirst()).allSatisfy { $0 != $1 })
        let japanese = GreetingView.sequence(for: "ja")
        #expect(japanese.first == "こんにちは" && japanese.last == "こんにちは")
        // A language Islet has no hello for starts in English.
        #expect(GreetingView.sequence(for: "eu").first == "Hello")
    }

    @Test func featuresStartOnFromWhatTheMacHas() {
        var found = Discovery()
        #expect(!found.suggested.contains(.agents) && !found.suggested.contains(.prompter) && !found.suggested.contains(.battery))
        found.agents = [.claude]
        found.usedSouffleur = true
        found.hasBattery = true
        found.aiApps = [AICatalog.apps[0]]
        #expect(found.suggested.isSuperset(of: [.agents, .prompter, .battery, .ai, .music]))
    }
}

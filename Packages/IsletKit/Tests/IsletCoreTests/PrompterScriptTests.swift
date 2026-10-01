import Foundation
import Testing
@testable import IsletCore

struct ScriptTests {
    /// The words of the script as the prompter shows them, in reading order.
    private func words(_ script: Script) -> [String] { script.words.map(\.text) }

    /// The text a range covers in what the prompter shows.
    private func shown(_ script: Script, _ range: NSRange) -> String {
        (script.display as NSString).substring(with: range)
    }

    @Test func splitsPlainTextIntoWordsWithTheirRanges() {
        let script = Script("Hello, world. It's a well-known place!")
        #expect(words(script) == ["Hello", "world", "It's", "a", "well-known", "place"])
        #expect(script.display == "Hello, world. It's a well-known place!")
        for word in script.words { #expect(shown(script, word.range) == word.text) }
    }

    @Test func cuesAreShownWithoutBracketsAndNeverSpoken() {
        let script = Script("Welcome [pause] to the show [smile]")
        #expect(words(script) == ["Welcome", "to", "the", "show"])
        #expect(script.display == "Welcome pause to the show smile")
        let cues = script.styles.filter { $0.kind == .cue }.map { shown(script, $0.range) }
        #expect(cues == ["pause", "smile"])
    }

    @Test func headingsAreShownButNeverSpoken() {
        let script = Script("# Intro\nGood morning\n## Part two\nThanks")
        #expect(words(script) == ["Good", "morning", "Thanks"])
        #expect(script.display == "Intro\nGood morning\nPart two\nThanks")
        let headings = script.styles.filter { $0.kind == .heading }.map { shown(script, $0.range) }
        #expect(headings == ["Intro", "Part two"])
    }

    @Test func boldMarkersAreRemovedAndTheWordsStaySpoken() {
        let script = Script("This is **really** important")
        #expect(script.display == "This is really important")
        #expect(words(script) == ["This", "is", "really", "important"])
        let emphasis = script.styles.filter { $0.kind == .emphasis }.map { shown(script, $0.range) }
        #expect(emphasis == ["really"])
    }

    @Test func anUnclosedMarkerStaysAsWritten() {
        let script = Script("Price [in dollars and 2 ** 3")
        #expect(script.display == "Price [in dollars and 2 ** 3")
        #expect(words(script) == ["Price", "in", "dollars", "and", "2", "3"])
    }

    @Test func rangesCountUTF16SoEmojiAndAccentsStayAligned() {
        let script = Script("Café 👋 déjà vu")
        #expect(words(script) == ["Café", "déjà", "vu"])
        for word in script.words { #expect(shown(script, word.range) == word.text) }
    }

    @Test func windowsLineEndingsBecomePlainNewlines() {
        let script = Script("One\r\nTwo")
        #expect(script.display == "One\nTwo")
        #expect(words(script) == ["One", "Two"])
    }

    @Test func anEmptyScriptHasNoWords() {
        #expect(Script("").isEmpty)
        #expect(Script("   \n\n  ").isEmpty)
        #expect(Script("# Only a heading\n[cue]").isEmpty)
        #expect(!Script("Hi").isEmpty)
    }

    @Test func numbersAndAmpersandsCountAsWords() {
        #expect(words(Script("We grew 25% in 2025 & beyond, 3.5 times")) == ["We", "grew", "25%", "in", "2025", "&", "beyond", "3.5", "times"])
    }

    @Test func eachWordKnowsItsLineOfSource() {
        let script = Script("First line\n\nThird line")
        #expect(script.words.map(\.paragraph) == [0, 0, 2, 2])
    }

    @Test func parsesTenThousandWordsQuickly() {
        let text = Array(repeating: "The quick **brown** fox [pause] jumps over the lazy dog.", count: 1250).joined(separator: "\n")
        let start = Date()
        let script = Script(text)
        #expect(script.words.count == 11_250)
        // About 30 ms in a debug build on an M3 Pro; the budget leaves room for shared CI machines and still fails at
        // once on anything quadratic, which would take seconds.
        #expect(Date().timeIntervalSince(start) < 0.5)
    }
}

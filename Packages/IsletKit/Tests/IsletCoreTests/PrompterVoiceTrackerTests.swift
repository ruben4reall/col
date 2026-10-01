import Foundation
import Testing
@testable import IsletCore

struct TranscriptTests {
    private let english = Transcript(locale: Locale(identifier: "en_US"))

    @Test func foldsCaseAccentsAndPunctuation() {
        #expect(english.tokens("Café, DÉJÀ vu!") == ["cafe", "deja", "vu"])
    }

    @Test func expandsContractions() {
        #expect(english.tokens("Don't worry, it's fine") == ["do", "not", "worry", "it", "is", "fine"])
        #expect(english.tokens("We can’t stop") == ["we", "can", "not", "stop"])
    }

    @Test func spellsOutNumbersSoDigitsMeetWords() {
        #expect(english.tokens("25") == english.tokens("twenty-five"))
        #expect(english.tokens("25%") == ["twenty", "five", "percent"])
        #expect(english.tokens("rock & roll") == ["rock", "and", "roll"])
    }

    @Test func spellsOutNumbersInTheScriptLanguage() {
        let french = Transcript(locale: Locale(identifier: "fr_FR"))
        #expect(french.tokens("25") == french.tokens("vingt-cinq"))
    }

    @Test func dropsFillersFromWhatWasHeard() {
        #expect(english.tokens("So um today uh we launch") == ["so", "today", "we", "launch"])
    }
}

struct VoiceTrackerTests {
    private func tracker(_ text: String) -> VoiceTracker {
        VoiceTracker(script: Script(text), locale: Locale(identifier: "en_US"))
    }

    @Test func advancesAsTheScriptIsRead() {
        var tracker = tracker("Hello and welcome to the show")
        #expect(tracker.wordIndex == 0)
        tracker.hear("hello")
        #expect(tracker.wordIndex == 1)
        tracker.hear("hello and welcome")
        #expect(tracker.wordIndex == 3)
        tracker.hear("hello and welcome to the show")
        #expect(tracker.wordIndex == 6)
        #expect(tracker.isFinished)
    }

    @Test func followsAcrossUtterances() {
        var tracker = tracker("Hello and welcome to the show")
        tracker.hear("hello and welcome")
        tracker.hear("to")
        #expect(tracker.wordIndex == 4)
        tracker.hear("to the show")
        #expect(tracker.isFinished)
    }

    @Test func digitsMatchNumbersWrittenInWords() {
        var tracker = tracker("We grew twenty-five percent this year")
        tracker.hear("we grew 25% this year")
        #expect(tracker.isFinished)
    }

    @Test func contractionsMatchTheLongForm() {
        var tracker = tracker("Please do not worry about it")
        tracker.hear("please don't worry about it")
        #expect(tracker.isFinished)
    }

    @Test func accentsAndCapitalsDoNotMatter() {
        var tracker = tracker("Café DÉJÀ vu tonight")
        tracker.hear("cafe deja vu tonight")
        #expect(tracker.isFinished)
    }

    @Test func fillersAreIgnored() {
        var tracker = tracker("So today we launch the new app")
        tracker.hear("so um today uh we launch")
        #expect(tracker.wordIndex == 4)
    }

    @Test func toleratesAMisheardWord() {
        var tracker = tracker("The quick brown fox jumps over the lazy dog")
        tracker.hear("the quack brown fox")
        #expect(tracker.wordIndex == 4)
    }

    @Test func repeatingASentenceNeverJumpsBack() {
        var tracker = tracker("One two three four five six seven eight")
        tracker.hear("one two three four five")
        #expect(tracker.wordIndex == 5)
        tracker.hear("three four five")
        #expect(tracker.wordIndex == 5)
    }

    @Test func improvisingDoesNotMoveTheScript() {
        var tracker = tracker("The quarterly results are strong and growing")
        tracker.hear("sorry let me grab some water first")
        #expect(tracker.wordIndex == 0)
    }

    @Test func anAsideEndingOnAWordAheadDoesNotJump() {
        var tracker = tracker("Today I want to share three ideas with you")
        tracker.hear("today i want to")
        #expect(tracker.wordIndex == 4)
        // "tell you" is said off script; "you" is in the script, five words on, but none of the words in between was said.
        tracker.hear("today i want to tell you")
        #expect(tracker.wordIndex == 4)
    }

    @Test func aRevisedPartialResultNeverMovesBackwards() {
        var tracker = tracker("Hello and welcome to the show")
        tracker.hear("hello and welcome")
        tracker.hear("hello and")
        #expect(tracker.wordIndex == 3)
    }

    @Test func aRepeatedWordResolvesToTheNearestOccurrenceAhead() {
        var tracker = tracker("the cat and the dog and the bird")
        tracker.hear("the cat")
        tracker.hear("the cat and the")
        #expect(tracker.wordIndex == 4)
    }

    @Test func skippingAParagraphReanchorsOnAStrongMatch() {
        let first = "Our first topic covers the history of the company and how the founders met in a small garage long ago."
        let second = "The second part explains every product we sell today and why our customers keep coming back for more."
        let third = "Finally we will look at the roadmap for next year with three big launches planned for spring."
        var tracker = tracker([first, second, third].joined(separator: "\n\n"))
        tracker.hear("our first topic")
        #expect(tracker.wordIndex == 3)
        let thirdStart = Script(first).words.count + Script(second).words.count
        // Two words from far ahead are not enough to jump.
        tracker.hear("finally we")
        #expect(tracker.wordIndex == 3)
        tracker.hear("finally we will look at the roadmap")
        #expect(tracker.wordIndex == thirdStart + 7)
    }

    @Test func aJumpSetsThePlaceByHand() {
        var tracker = tracker("One two three four five six")
        tracker.jump(toWord: 4)
        tracker.hear("five")
        #expect(tracker.wordIndex == 5)
    }

    @Test func anEmptyScriptIsFinishedFromTheStart() {
        let tracker = tracker("# Just a title")
        #expect(tracker.isFinished)
    }
}

struct RecognitionLocalesTests {
    private func ids(_ locales: [Locale]) -> [String] {
        locales.map { [$0.language.languageCode?.identifier, $0.region?.identifier].compactMap { $0 }.joined(separator: "_") }
    }

    @Test func triesTheReadersRegionThenTheLanguagesUsualOne() {
        let supported = [Locale(identifier: "en-GB"), Locale(identifier: "en-US"), Locale(identifier: "en-AU"), Locale(identifier: "fr-FR")]
        // An English script on a Mac set to Switzerland: no Swiss English model, so American before the others.
        let candidates = RecognitionLocales.candidates(for: Locale(identifier: "en"), supported: supported, current: Locale(identifier: "en_CH"))
        #expect(ids(candidates) == ["en", "en_US", "en_AU", "en_GB"])
    }

    @Test func keepsTheRegionAskedForFirst() {
        let supported = [Locale(identifier: "fr-FR"), Locale(identifier: "fr-CH"), Locale(identifier: "fr-CA")]
        let candidates = RecognitionLocales.candidates(for: Locale(identifier: "fr_CH"), supported: supported, current: Locale(identifier: "fr_CH"))
        #expect(ids(candidates) == ["fr_CH", "fr_FR", "fr_CA"])
    }
}

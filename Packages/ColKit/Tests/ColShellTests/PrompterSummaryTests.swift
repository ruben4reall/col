import Foundation
import Testing
@testable import ColPrompter

struct PrompterSummaryTests {
    @Test func souffleursLastTakeCarriesOverInColsLanguage() throws {
        // Souffleur always wrote it in English; Col writes it again with its own words for "wpm" and the percentage.
        let summary = try #require(PrompterPreferences.lastTake(fromSouffleur: "1:23 · 140 wpm · 92%"))
        #expect(summary.hasPrefix("1:23 · 140 "))
        #expect(summary.contains("92"))
        #expect(summary.hasSuffix("%"))
        #expect(PrompterPreferences.lastTake(fromSouffleur: "1:02:03 · 98 wpm · 100%") != nil)
    }

    @Test func aSummaryThatReadsOtherwiseIsLeftBehind() {
        for summary in ["", "1:23", "1:23 · 140 wpm", "1:23 · fast · 92%", "1:23 · 140 wpm · most", "soon · 140 wpm · 92%"] {
            #expect(PrompterPreferences.lastTake(fromSouffleur: summary) == nil, "\(summary)")
        }
    }
}

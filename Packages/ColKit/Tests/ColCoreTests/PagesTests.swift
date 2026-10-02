import Foundation
import Testing
@testable import ColCore

struct PagesTests {
    @Test func aStackShowsItsFirstWidgetWithSomethingToShow() {
        let stack = WidgetStack([.music, .clock])
        #expect(stack.shown { $0 == .music || $0 == .clock } == .music)
        #expect(stack.shown { $0 == .clock } == .clock)
    }

    @Test func aStackFallsBackOnItsLastWidget() {
        #expect(WidgetStack([.music]).shown { _ in false } == .music)
        #expect(WidgetStack([]).shown { _ in true } == nil)
    }

    @Test func islet1PagesBecomePagesInTheSameOrder() {
        let deck = PageDeck.migrating(enabledPages: ["tools", "shelf", "unknown", "tools"])
        #expect(deck.pages.map(\.id) == [PageDeck.homeID, "tools", "shelf"])
        #expect(deck.pages[1].stacks == [WidgetStack([.tools])])
    }

    @Test func validationDropsWhatAPlaceCannotHold() {
        let deck = PageDeck(pages: [
            // The clock cannot fill a page; a repeated widget appears once.
            PageLayout(id: "a", stacks: [WidgetStack([.clock, .agenda, .agenda])]),
            // The shelf cannot share a page; left alone, the clock cannot fill one: nothing is left, the page goes.
            PageLayout(id: "b", stacks: [WidgetStack([.shelf]), WidgetStack([.clock])]),
            // The agenda can do both: it stays, across the page.
            PageLayout(id: "c", stacks: [WidgetStack([.system]), WidgetStack([.agenda])]),
            // A repeated id goes.
            PageLayout(id: "a", stacks: [WidgetStack([.system])]),
        ]).validated()
        #expect(deck.pages.map(\.id) == ["a", "c"])
        #expect(deck.pages[0].stacks == [WidgetStack([.agenda])])
        #expect(deck.pages[1].stacks == [WidgetStack([.agenda])])
    }

    @Test func aDeckKeepsAtLeastOnePage() {
        #expect(PageDeck(pages: []).validated().pages.map(\.id) == [PageDeck.homeID])
        var deck = PageDeck(pages: [PageLayout(id: "only", stacks: [WidgetStack([.system])])])
        deck.remove("only")
        #expect(deck.pages.count == 1)
    }

    @Test func columnsSplitAndMergeKeepingWhatFits() {
        var page = PageLayout(id: "p", stacks: [WidgetStack([.music, .clock]), WidgetStack([.agenda])])
        page.setColumns(1)
        #expect(page.stacks == [WidgetStack([.music, .agenda])])
        page.setColumns(2)
        #expect(page.stacks == [WidgetStack([.music]), WidgetStack([.agenda])])
        var shelf = PageLayout(id: "s", stacks: [WidgetStack([.shelf])])
        shelf.setColumns(2)
        #expect(shelf.stacks == [WidgetStack([.clock]), WidgetStack([.agenda])])
    }

    @Test func pagesMoveAndAreFoundByWidget() {
        var deck = PageDeck.standard
        deck.move("system", by: -10)
        #expect(deck.pages.first?.id == "system")
        #expect(deck.firstPage(holding: .shelf)?.id == "shelf")
        #expect(deck.firstPage(holding: .clock)?.id == PageDeck.homeID)
    }

    @Test func aDeckSurvivesItsOwnEncoding() throws {
        let data = try JSONEncoder().encode(PageDeck.standard)
        #expect(try JSONDecoder().decode(PageDeck.self, from: data) == PageDeck.standard)
    }
}

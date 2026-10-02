import Foundation
import Testing
@testable import ColShell

struct AskTests {
    @Test func readsOllamasLines() {
        #expect(ModelChat.ollamaPiece(#"{"message":{"role":"assistant","content":"Hello"},"done":false}"#) == "Hello")
        #expect(ModelChat.ollamaPiece(#"{"message":{"role":"assistant","content":""},"done":true}"#) == nil)
        #expect(ModelChat.ollamaPiece("not json") == nil)
    }

    @Test func readsOpenAIEvents() {
        #expect(ModelChat.openAIPiece(#"data: {"choices":[{"delta":{"content":"Hi"}}]}"#) == "Hi")
        #expect(ModelChat.openAIPiece("data: [DONE]") == nil)
        #expect(ModelChat.openAIPiece(": keep-alive") == nil)
        #expect(ModelChat.openAIPiece(#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == nil)
    }

    @Test func thinkingAloudStaysOutOfSight() {
        #expect(AskSession.shown("<think>Let me see</think>\n\nParis.") == ("Paris.", false))
        #expect(AskSession.shown("<think>Still weigh") == ("", true))
        #expect(AskSession.shown("Plain answer") == ("Plain answer", false))
        #expect(AskSession.shown("<think>a</think>One <think>b</think>two") == ("One two", false))
    }
}

struct AskLinkTests {
    private func links(_ markdown: String) -> [URL] {
        AskSession.markdown(markdown).runs.compactMap(\.link)
    }

    @Test func webLinksStayLinks() {
        #expect(links("See [the docs](https://example.com/docs) and [this](http://mac-studio.lan:8080/).")
            == [URL(string: "https://example.com/docs")!, URL(string: "http://mac-studio.lan:8080/")!])
        #expect(links("<HTTPS://EXAMPLE.COM>") == [URL(string: "HTTPS://EXAMPLE.COM")!])
    }

    @Test func otherLinksKeepOnlyTheirWords() {
        let answer = "[the docs](col://prompter/prompt?text=hi), [open](file:///Applications/Calculator.app), "
            + "[here](smb://host/share), [mail](mailto:a@b.c), <islet://clipboard> and [x](javascript:alert(1))"
        let shown = AskSession.markdown(answer)
        #expect(shown.runs.compactMap(\.link).isEmpty)
        #expect(String(shown.characters) == "the docs, open, here, mail, islet://clipboard and x")
    }

    @Test func emphasisAndCodeAreKept() {
        let shown = AskSession.markdown("Use `swift test` **now**, see [it](https://swift.org).")
        #expect(String(shown.characters) == "Use swift test now, see it.")
        #expect(shown.runs.contains { $0.inlinePresentationIntent == .code })
        #expect(shown.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    @Test func onlyTheWebOpens() {
        #expect(AskSession.opensOnTheWeb(URL(string: "https://example.com")!))
        #expect(AskSession.opensOnTheWeb(URL(string: "HTTP://example.com")!))
        #expect(!AskSession.opensOnTheWeb(URL(string: "file:///etc/hosts")!))
        #expect(!AskSession.opensOnTheWeb(URL(string: "col://settings")!))
    }
}

import Testing
@testable import IsletShell

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

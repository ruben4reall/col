import Foundation
import Testing
@testable import ColPrompter

struct RemotePageTests {
    @Test func thePageSpeaksTheLanguageItIsGiven() {
        var words = RemotePage.Words()
        words.connecting = "Connexion à votre Mac…"
        words.pace = "%lld mots/min"
        let page = RemotePage.html(words: words, language: "fr")
        #expect(page.contains(#"<html lang="fr">"#))
        #expect(page.contains(#"<div class="line empty" id="line">Connexion à votre Mac…</div>"#))
        #expect(page.contains(#""pace":"%lld mots\/min""#))
    }

    @Test func wordsCannotBreakThePage() {
        var words = RemotePage.Words()
        words.slower = #"<b>"Slower"</b> & 'more'"#
        words.pressPlay = "</script><script>alert(1)</script>"
        let page = RemotePage.html(words: words, language: "en")
        #expect(page.contains("&lt;b&gt;&quot;Slower&quot;&lt;/b&gt; &amp; &#39;more&#39;"))
        // The only closing tag of a script is the page's own.
        #expect(page.components(separatedBy: "</script>").count == 2)
    }
}

import Foundation

/// The page a phone opens from Connect's pairing code: the Mac's address and the device's token, to copy into a
/// Shortcut or another app, and a button that sends a first activity to the island. The token stays in the address's
/// fragment, read by the page on the phone: the request for the page never carries it, and the page holds no secret.
enum ConnectPage {
    struct Words: Encodable {
        var title = String(localized: "Col Connect", bundle: .module)
        var intro = String(localized: "This phone is paired with Col. Copy the address and the token into a Shortcut’s Get Contents of URL action, or into any app that calls a web address.", bundle: .module)
        var address = String(localized: "Address", bundle: .module)
        var token = String(localized: "Token", bundle: .module)
        var header = String(localized: "Send it in a header: Authorization: Bearer, then the token.", bundle: .module)
        var copy = String(localized: "Copy", bundle: .module)
        var copied = String(localized: "Copied", bundle: .module)
        var test = String(localized: "Send a Test to the Island", bundle: .module)
        var sent = String(localized: "Look at the notch of your Mac.", bundle: .module)
        var failed = String(localized: "Col did not answer. Is Connect still on, and the phone on the same network?", bundle: .module)
        var missing = String(localized: "Scan the code in Col’s settings again: this page needs the token it carries.", bundle: .module)
        var hello = String(localized: "Hello from your phone", bundle: .module)
    }

    static var html: String {
        html(words: Words(), language: Bundle.module.preferredLocalizations.first ?? "en")
    }

    static func html(words: Words, language: String) -> String {
        // In the script, as JSON: its slashes are escaped, so no word can close the <script> element.
        let script = (try? JSONEncoder().encode(words)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        <!doctype html>
        <html lang="\(escape(language))">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="light dark">
        <link rel="icon" href="data:,">
        <title>\(escape(words.title))</title>
        <style>
        :root { color-scheme: light dark; --bg: #f2f2f7; --card: #fff; --ink: #000; --dim: rgba(60,60,67,.6); --accent: #0a84ff; }
        @media (prefers-color-scheme: dark) { :root { --bg: #000; --card: #1c1c1e; --ink: #fff; --dim: rgba(235,235,245,.6); } }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--ink); font: 17px/1.4 -apple-system, BlinkMacSystemFont, system-ui, sans-serif; }
        main { max-width: 520px; margin: 0 auto; padding: max(24px, env(safe-area-inset-top)) 16px 32px; }
        h1 { font-size: 28px; margin: 8px 0 8px; letter-spacing: -.02em; }
        p { color: var(--dim); margin: 0 0 20px; }
        .card { background: var(--card); border-radius: 14px; padding: 14px 16px; margin-bottom: 14px; }
        .label { font-size: 13px; color: var(--dim); margin-bottom: 4px; }
        .row { display: flex; gap: 10px; align-items: center; }
        code { flex: 1; font: 15px ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; }
        button { appearance: none; border: 0; border-radius: 10px; background: rgba(120,120,128,.16); color: var(--accent);
          font: 600 15px -apple-system, system-ui, sans-serif; padding: 8px 12px; }
        .primary { width: 100%; background: var(--accent); color: #fff; padding: 14px; font-size: 17px; border-radius: 12px; }
        .note { font-size: 14px; color: var(--dim); margin-top: 12px; min-height: 20px; }
        </style>
        </head>
        <body>
        <main>
          <h1>\(escape(words.title))</h1>
          <p id="intro">\(escape(words.intro))</p>
          <div class="card"><div class="label">\(escape(words.address))</div>
            <div class="row"><code id="address"></code><button data-copy="address">\(escape(words.copy))</button></div></div>
          <div class="card"><div class="label">\(escape(words.token))</div>
            <div class="row"><code id="token"></code><button data-copy="token">\(escape(words.copy))</button></div>
            <div class="note">\(escape(words.header))</div></div>
          <button class="primary" id="test">\(escape(words.test))</button>
          <div class="note" id="result"></div>
        </main>
        <script>
        const T = \(script);
        const $ = id => document.getElementById(id);
        const token = decodeURIComponent(location.hash.slice(1));
        $("address").textContent = location.origin;
        $("token").textContent = token;
        if (!token) { $("intro").textContent = T.missing; $("test").disabled = true; }
        document.querySelectorAll("button[data-copy]").forEach(b => b.addEventListener("click", async () => {
          // The clipboard API needs https: over the local network's http, the text is selected and copied the old way.
          try { await navigator.clipboard.writeText($(b.dataset.copy).textContent); b.textContent = T.copied; }
          catch (_) {
            const r = document.createRange(); r.selectNodeContents($(b.dataset.copy));
            getSelection().removeAllRanges(); getSelection().addRange(r);
            if (document.execCommand("copy")) b.textContent = T.copied;
          }
        }));
        $("test").addEventListener("click", async () => {
          try {
            const answer = await fetch("/v1/activities", { method: "POST", cache: "no-store",
              headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
              body: JSON.stringify({ id: "connect-test", title: T.hello, symbol: "iphone", tint: "blue", text: "Col", ttl: 8 }) });
            $("result").textContent = answer.ok ? T.sent : T.failed;
          } catch (_) { $("result").textContent = T.failed; }
        });
        </script>
        </body>
        </html>
        """
    }

    /// Text set in the page's markup, with the characters HTML gives a meaning to written as entities.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

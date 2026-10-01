/// The page the phone remote opens: one file, no external resources, served by `RemoteServer`.
enum RemotePage {
    static let html = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
    <meta name="theme-color" content="#08080a">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <link rel="icon" href="data:,">
    <title>Col Prompter Remote</title>
    <style>
    :root { --accent: #9d84ff; --fuchsia: #ff5ac8; --ink: #f7f7fa; --dim: rgba(235,235,245,.55); --faint: rgba(235,235,245,.28); --well: rgba(255,255,255,.08); }
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body { margin: 0; height: 100%; background: radial-gradient(120% 60% at 50% 0%, rgba(143,107,255,.16), transparent 60%), #08080a; color: var(--ink);
      font: 16px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; -webkit-user-select: none; user-select: none; }
    main { min-height: 100%; display: flex; flex-direction: column; padding: max(20px, env(safe-area-inset-top)) 20px max(24px, env(safe-area-inset-bottom)); gap: 18px; }
    header { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
    .brand { font-weight: 650; letter-spacing: -.01em; font-size: 15px; display: flex; align-items: center; gap: 8px; }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--faint); transition: background .3s; }
    .dot.live { background: var(--accent); box-shadow: 0 0 12px rgba(157,132,255,.8); }
    .title { color: var(--dim); font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 55%; }
    .line { flex: 1; display: flex; align-items: center; justify-content: center; text-align: center;
      font-size: clamp(22px, 7vw, 34px); font-weight: 600; letter-spacing: -.015em; line-height: 1.25; padding: 8px 4px; min-height: 30vh; }
    .line.empty { color: var(--faint); font-weight: 500; font-size: 18px; }
    .meta { display: flex; justify-content: space-between; color: var(--dim); font-size: 13px; font-variant-numeric: tabular-nums; }
    .bar { height: 4px; border-radius: 2px; background: var(--well); overflow: hidden; }
    .bar i { display: block; height: 100%; width: 0; background: linear-gradient(90deg, var(--accent), var(--fuchsia)); border-radius: 2px; transition: width .4s ease; }
    .controls { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; align-items: center; justify-items: center; }
    button { appearance: none; border: 0; color: var(--ink); background: var(--well); border-radius: 22px; width: 100%; height: 64px;
      font: 600 15px/1 inherit; display: flex; align-items: center; justify-content: center; gap: 8px; transition: transform .12s, background .2s; }
    button:active { transform: scale(.96); background: rgba(255,255,255,.14); }
    button svg { width: 22px; height: 22px; fill: currentColor; }
    .play { grid-column: 2; width: 96px; height: 96px; border-radius: 50%; background: linear-gradient(135deg, var(--accent), var(--fuchsia)); color: #fff; box-shadow: 0 10px 40px rgba(179,92,255,.45); }
    .play:active { filter: brightness(.9); }
    .play svg { width: 34px; height: 34px; }
    .offline { position: fixed; left: 50%; top: 14px; transform: translateX(-50%); background: #2a2a2e; color: var(--dim);
      font-size: 13px; padding: 8px 14px; border-radius: 99px; opacity: 0; transition: opacity .3s; pointer-events: none; }
    .offline.show { opacity: 1; }
    </style>
    </head>
    <body>
    <main>
      <header>
        <div class="brand"><span class="dot" id="dot"></span>Col</div>
        <div class="title" id="title"></div>
      </header>
      <div class="line empty" id="line">Connecting to your Mac…</div>
      <div>
        <div class="meta"><span id="left">0%</span><span id="pace"></span><span id="remaining"></span></div>
        <div class="bar"><i id="progress"></i></div>
      </div>
      <div class="controls">
        <button data-action="back" aria-label="Previous line"><svg viewBox="0 0 24 24"><path d="M15.4 5.4 14 4l-8 8 8 8 1.4-1.4L8.8 12z"/></svg></button>
        <button class="play" data-action="toggle" aria-label="Play or pause" id="play"><svg viewBox="0 0 24 24" id="playIcon"><path d="M8 5v14l11-7z"/></svg></button>
        <button data-action="forward" aria-label="Next line"><svg viewBox="0 0 24 24"><path d="M8.6 5.4 10 4l8 8-8 8-1.4-1.4 6.6-6.6z"/></svg></button>
        <button data-action="slower" aria-label="Slower">Slower</button>
        <button data-action="restart" aria-label="Restart"><svg viewBox="0 0 24 24"><path d="M12 5V1L7 6l5 5V7a5 5 0 1 1-5 5H5a7 7 0 1 0 7-7z"/></svg></button>
        <button data-action="faster" aria-label="Faster">Faster</button>
      </div>
    </main>
    <div class="offline" id="offline">Reconnecting to your Mac…</div>
    <script>
    const token = new URLSearchParams(location.search).get("token") || "";
    const $ = id => document.getElementById(id);
    const clock = s => { s = Math.max(0, Math.round(s)); const m = Math.floor(s / 60); return m + ":" + String(s % 60).padStart(2, "0"); };
    const pause = '<path d="M7 5h4v14H7zm6 0h4v14h-4z"/>', play = '<path d="M8 5v14l11-7z"/>';
    function render(s) {
      $("title").textContent = s.title || "";
      // Nothing open on the Mac: the play button below opens the selected script.
      const idle = !s.isActive, line = $("line");
      line.textContent = idle ? (s.title ? "Press play to start." : "Choose a script in Col.") : s.line;
      line.classList.toggle("empty", idle || !s.line);
      $("progress").style.width = (idle ? 0 : s.progress * 100).toFixed(1) + "%";
      $("left").textContent = idle ? "" : Math.round(s.progress * 100) + "%";
      $("pace").textContent = !idle && s.wordsPerMinute ? Math.round(s.wordsPerMinute) + " wpm" : "";
      $("remaining").textContent = idle ? "" : "−" + clock(s.remaining);
      $("playIcon").innerHTML = s.isRolling ? pause : play;
      $("dot").classList.toggle("live", s.isRolling);
    }
    document.querySelectorAll("button[data-action]").forEach(b => b.addEventListener("click", () => {
      if (navigator.vibrate) navigator.vibrate(8);
      fetch("/command?token=" + encodeURIComponent(token) + "&action=" + b.dataset.action, { cache: "no-store" }).catch(() => {});
    }));
    function connect() {
      const events = new EventSource("/events?token=" + encodeURIComponent(token));
      events.onopen = () => $("offline").classList.remove("show");
      events.onmessage = e => { try { render(JSON.parse(e.data)); } catch (_) {} };
      events.onerror = () => { $("offline").classList.add("show"); };
    }
    connect();
    </script>
    </body>
    </html>
    """
}

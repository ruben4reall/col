#!/bin/bash
# scripts/capture-site.sh: photographs and films the real app for the website, then lays the island on a real macOS
# desktop (COL_DESKTOP, a 3024 x 1964 PNG) and writes the WebP pictures and MP4 films the website and the README use.
# While the island is photographed, that same desktop covers the screen just under it, so its glass shows the website's
# desktop and nothing of the Mac the pictures are taken on.
# Nothing is drawn by hand: each picture is Col itself, in English, driven by its debug switches and its local API,
# with a silent demo track, demo files and original lyrics, so no sound and no personal data (calendar, clipboard,
# library) appear. The Col already running is quit first and opened again at the end.
set -uo pipefail
cd "$(dirname "$0")/.."
BUILD="${COL_BUILD_DIR:-.build/xcode}"
[[ "$BUILD" = /* ]] || BUILD="$PWD/$BUILD"
APP="$BUILD/Build/Products/Debug/Col.app"
DESKTOP="${COL_DESKTOP:?set COL_DESKTOP to a 3024 x 1964 PNG of a macOS desktop}"
OUT=.build/site-shots
TMP=$(mktemp -d)
mkdir -p "$OUT"
[ -d "$APP" ] || scripts/build.sh >/dev/null
# A socket of its own: the captures never reach another copy.
export COL_SOCKET="$TMP/col.sock"
COLCTL="$APP/Contents/Helpers/colctl"
# The user's own copy (Col, or Islet before 2.0), quit now and opened again at the end.
USER_APP=$(ps -axo command= | grep -E -m1 "/(Col|Islet)\.app/Contents/MacOS/(Col|Islet)$" | grep -v "$APP" | sed -E 's|/Contents/MacOS/[^/]+$||' || true)
[ -n "$USER_APP" ] && osascript -e "tell application \"$USER_APP\" to quit" >/dev/null 2>&1 && sleep 2
SUPPORT="$HOME/Library/Application Support/Col"
SUPPORT_EXISTED=$([ -d "$SUPPORT" ] && echo 1 || echo 0)
LYRICS="$SUPPORT/Lyrics/Sunset Avenue - Golden Hour.lrc"
PLAYER= BACKDROP=
# Whatever happens, the desktop over the screen and the demo track go, the lyrics and any folder the captures made
# leave, and the user's copy comes back.
cleanup() {
  kill $PLAYER $BACKDROP 2>/dev/null
  pkill -f "$APP/Contents/MacOS/Col" 2>/dev/null
  sleep 1
  rm -f "$LYRICS"
  if [ "$SUPPORT_EXISTED" = 0 ] && [ -d "$SUPPORT" ]; then mv "$SUPPORT" "$HOME/.Trash/Col-captures-$(date +%s)"; fi
  rm -rf "$TMP"
  [ -n "$USER_APP" ] && open -g "$USER_APP"
}
trap cleanup EXIT

# Every Col window of the capture on screen: "id layer x y width height", in points.
windows() {
  swift - "$APP" <<'SWIFT' 2>/dev/null
import AppKit
import CoreGraphics
let path = CommandLine.arguments[1]
let mine = Set(NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path.hasSuffix(path) ?? false }.map(\.processIdentifier))
for w in CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]] {
    guard let pid = w["kCGWindowOwnerPID"] as? pid_t, mine.contains(pid) else { continue }
    let b = w["kCGWindowBounds"] as! [String: Double]
    print(w["kCGWindowNumber"]!, w["kCGWindowLayer"]!, Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!))
}
SWIFT
}
# shoot <island|prompter|window> <name>: the island hangs from the top of the screen, the prompter just above it,
# windows are the largest one at the normal level.
shoot() {
  local line id layer x y w h
  case "$1" in
    island) line=$(windows | awk '$2==27 && $4==0' | head -1) ;;
    prompter) line=$(windows | awk '$2==28 && $4==0' | head -1) ;;
    window) line=$(windows | awk '$2==0' | sort -k5 -n -r | head -1) ;;
  esac
  [ -n "$line" ] || { echo "  $2: no window"; return 0; }
  read -r id layer x y w h <<< "$line"
  screencapture -x -o -l "$id" "$OUT/$2.png"
  # The island: what shows through its glass comes from the screen, where the website's desktop lies under it.
  if [ "$1" = island ]; then
    screencapture -x -R "$x,$y,$w,$h" "$TMP/screen.png"
    swift scripts/glass-merge.swift "$OUT/$2.png" "$TMP/screen.png" >/dev/null 2>&1
  fi
  echo "  $2"
}
hex() { python3 -c 'import json, sys; print(json.dumps(json.loads(sys.argv[1])).encode().hex())' "$1"; }
DECK=$(hex '{"pages":[{"id":"home","symbol":"house.fill","stacks":[{"widgets":["music","clock"]},{"widgets":["lyrics","agenda"]}]},{"id":"prompter","stacks":[{"widgets":["prompter"]}]},{"id":"ai","stacks":[{"widgets":["ai"]}]},{"id":"shelf","stacks":[{"widgets":["shelf"]}]},{"id":"clipboard","stacks":[{"widgets":["clipboard"]}]},{"id":"tools","stacks":[{"widgets":["tools"]}]}]}')
SERVERS=$(hex '[{"id":"studio","name":"Mac Studio","kind":"ollama","address":"http://127.0.0.1:11434","usesToken":false},{"id":"lab","name":"Workstation","kind":"llamaCpp","address":"http://127.0.0.1:8080","usesToken":false}]')
# Liquid glass unless GLASS says otherwise, whatever the user chose; the demo pages and model servers.
run() {
  pkill -f "$APP/Contents/MacOS/Col" 2>/dev/null; sleep 0.6
  ("$APP/Contents/MacOS/Col" -AppleLanguages '(en)' -AppleLocale en_US -islandGlass "${GLASS:-liquid}" -pageDeck "<$DECK>" \
    -aiServers "<$SERVERS>" -askModel "studio
qwen3:8b" -showsLyricsInClosedIsland "${LYRICS_CLOSED:-NO}" -keepsClipboardHistory YES -ColWallpaper "$DESKTOP" \
    "$@" >/dev/null 2>&1 &)
  for _ in {1..60}; do curl -s --unix-socket "$COL_SOCKET" http://col/v1/status >/dev/null 2>&1 && break; sleep 0.2; done
}
# The demo track, restarted before each capture of the player so every picture shows the same moment of the song.
player() {
  [ -n "$PLAYER" ] && kill "$PLAYER" 2>/dev/null
  ALBUM="Long Light" swift scripts/fake-player.swift "Golden Hour" "Sunset Avenue" 214 "$TMP/cover.png" >/dev/null 2>&1 &
  PLAYER=$!
  sleep 3
}
post() { curl -s --unix-socket "$COL_SOCKET" -X POST "http://col/v1/agents/events?agent=$1" -d "$2" >/dev/null; }
pid() { pgrep -f "$APP/Contents/MacOS/Col" | head -1; }
backdrop() {
  [ -n "$BACKDROP" ] && kill "$BACKDROP" 2>/dev/null
  swift scripts/desktop-backdrop.swift "$DESKTOP" "$@" >/dev/null 2>&1 &
  BACKDROP=$!
  sleep 3
}
film() { swift scripts/record-film.swift "$OUT/$1.mov" "$2" "$(pid),$(pgrep -f desktop-backdrop | paste -sd, -)" "$3" 0 "$4" "$5" >/dev/null 2>&1; echo "  $1 (film)"; }

# Original lyrics, written for these pictures, read from the folder Col prefers to LRCLIB.
mkdir -p "$(dirname "$LYRICS")"
cat > "$LYRICS" <<'LRC'
[00:00.00] Streetlights waking one by one
[00:02.60] We drive into the golden hour
[00:05.20] Windows down and nowhere to be
[00:07.80] Into the blue
[00:10.40] Hold the light a little longer
[00:13.00] Before the city turns to blue
[00:15.60] Every song sounds like a summer
[00:18.20] Every road leads back to you
[00:20.80] Streetlights waking one by one
[00:23.40] We drive into the golden hour
LRC
swift brand/scripts/demo-cover.swift "$TMP/cover.png"
# Demo files for the shelf (a brief, a photo, a note), and the pieces of macOS the website's scenes use.
swift brand/scripts/demo-files.swift "$TMP/files" "$TMP/cover.png" >/dev/null
mkdir -p "$TMP/none" "$TMP/one"
cp "$TMP/files/Brief.pdf" "$TMP/one/"
# A model server that answers like Ollama and llama.cpp, word by word, on this Mac only.
python3 - >/dev/null 2>&1 <<'PY' &
import http.server, json, threading, time
ANSWER = "Here is a **short** answer: an island keeps what matters in sight, and `Col` stays out of the way. Ask again for more.".split(" ")
class Ollama(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        routes = {"/api/version": {"version": "0.12.3"}, "/api/tags": {"models": [{"name": "qwen3:8b"}, {"name": "llama3.2:3b"}]},
                  "/api/ps": {"models": [{"name": "qwen3:8b", "size_vram": 5800000000}]}}
        body = routes.get(self.path)
        self.send_response(200 if body else 404); self.send_header("Content-Type", "application/json"); self.end_headers()
        if body: self.wfile.write(json.dumps(body).encode())
    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        self.send_response(200); self.send_header("Content-Type", "application/x-ndjson"); self.end_headers()
        for piece in [w + " " for w in ANSWER]:
            self.wfile.write((json.dumps({"model": request["model"], "message": {"role": "assistant", "content": piece}, "done": False}) + "\n").encode())
            self.wfile.flush(); time.sleep(0.06)
        self.wfile.write((json.dumps({"model": request["model"], "message": {"role": "assistant", "content": ""}, "done": True}) + "\n").encode())
class Llama(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        body = {"/slots": [{"id": 0, "is_processing": True}], "/v1/models": {"data": [{"id": "gpt-oss-20b"}]}}.get(self.path)
        self.send_response(200 if body else 404); self.send_header("Content-Type", "application/json"); self.end_headers()
        if body: self.wfile.write(json.dumps(body).encode())
servers = [http.server.ThreadingHTTPServer(("127.0.0.1", 11434), Ollama), http.server.ThreadingHTTPServer(("127.0.0.1", 8080), Llama)]
for s in servers: threading.Thread(target=s.serve_forever, daemon=True).start()
time.sleep(1200)
PY
MODELS=$!
trap 'kill $MODELS 2>/dev/null; cleanup' EXIT

echo "Island:"
backdrop
# At rest first, before the demo track: the island is the notch itself, its exact shape.
run; sleep 3; shoot island rest
player; sleep 2
player; run; sleep 3; shoot island music-compact
# A short line, whole in the wing, whatever room the menu bar leaves it.
player; LYRICS_CLOSED=YES run; sleep 4; shoot island lyrics-compact
player; run -ColOpen YES; sleep 3; shoot island home-open
run -ColDemo headphones; sleep 6; shoot island airpods-pro
run -ColDemo max; sleep 6; shoot island airpods-max
run; sleep 1; "$COLCTL" push build --title Build --symbol hammer.fill --tint orange --progress 40% >/dev/null; sleep 2; shoot island push-build
# Agents: a request first, then one at work, then four at once.
run -ColOpen YES -ColPage live; sleep 1
# In a background list the shell would give the hook an empty stdin: the pipe stays inside the subshell.
(echo '{"session_id":"site","hook_event_name":"PermissionRequest","cwd":"/Users/me/col","tool_name":"Bash","tool_input":{"command":"git push origin main","description":"Push the release"}}' \
  | "$COLCTL" hook >/dev/null 2>&1) &
sleep 3; shoot island agent-request
pkill -f "Helpers/colctl hook" 2>/dev/null
run; sleep 1
post claude '{"session_id":"c1","hook_event_name":"UserPromptSubmit","cwd":"/Users/me/col"}'
post claude '{"session_id":"c1","hook_event_name":"PreToolUse","cwd":"/Users/me/col","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
sleep 2; shoot island claude-working
post codex '{"session_id":"x1","hook_event_name":"UserPromptSubmit","cwd":"/Users/me/api"}'
sleep 2; shoot island agents-compact
run -ColOpen YES -ColPage live; sleep 1
post claude '{"session_id":"c1","hook_event_name":"UserPromptSubmit","cwd":"/Users/me/col"}'
post claude '{"session_id":"c1","hook_event_name":"PreToolUse","cwd":"/Users/me/col","tool_name":"Bash","tool_input":{"command":"swift test"}}'
post codex '{"session_id":"x1","hook_event_name":"UserPromptSubmit","cwd":"/Users/me/api"}'
post gemini '{"session_id":"g1","hook_event_name":"BeforeAgent","cwd":"/Users/me/notes"}'
post gemini '{"session_id":"g1","hook_event_name":"Notification","cwd":"/Users/me/notes","notification_type":"ToolPermission","message":"Gemini wants to run npm install"}'
post copilot '{"session_id":"v1","hook_event_name":"UserPromptSubmit","cwd":"/Users/me/site","prompt":"Fix the test"}'
sleep 2; shoot island live-agents
# Your own models: the AI page, then a question asked from the island.
run -ColOpen YES -ColPage ai; sleep 4; shoot island ai-page
run -ColOpen YES -ColPage ai -ColAsk "How do I keep a script running after I close the terminal?"; sleep 5; shoot island ask
# The shelf and the clipboard, with demo content only: the user's shelf and pasteboard are never read.
run -ColDemoShelf "$TMP/none" -ColDemo drop -ColOpen YES -ColPage shelf; sleep 3; shoot island shelf-drop
run -ColDemoShelf "$TMP/one" -ColOpen YES -ColPage shelf; sleep 3; shoot island shelf-one
run -ColDemo clipboard -ColDemoImage "$TMP/cover.png" -ColOpen YES -ColPage clipboard; sleep 3; shoot island clipboard
run -ColOpen YES -ColPage tools; sleep 3; shoot island tools
player; run -ColOpen YES -islandSize compact; sleep 3; shoot island size-compact
player; run -ColOpen YES -islandSize large; sleep 3; shoot island size-large
# The prompter, rolling out of the notch: a picture, then a film.
SCRIPT="Good morning, everyone. Today we are introducing Col, the notch, made useful. It lives right under your camera, so your eyes stay on the people you talk to. Your script rolls at the pace of your voice, and waits whenever you stop. Nobody watching ever sees it: it stays out of your screenshots, your recordings and your calls."
run -ColPrompt "$SCRIPT" -ColPromptTitle "Launch video"; sleep 3.2; shoot prompter prompter
run -ColPrompt "$SCRIPT" -ColPromptTitle "Launch video"; film prompter 9 476 560 210
# The lyrics following the song, the island open on Home.
player; run -ColOpen YES; film lyrics 11 432 648 228
# The four kinds of glass, over the lake and its rocks (the desktop raised by 440 points), where the glass has
# something to bend: the website shows them on the same part of the desktop.
backdrop 440
for glass in liquid transparent tinted off; do
  name=$glass; [ "$glass" = off ] && name=black
  player; GLASS=$glass run -ColOpen YES; sleep 3; shoot island "glass-$name"
done
kill "$BACKDROP" 2>/dev/null; BACKDROP=

echo "Windows:"
# Where a copy comes from, for the clipboard scene: a real TextEdit window with its text selected. Only when TextEdit
# is not already open, so the user's documents are never touched.
if ! pgrep -x TextEdit >/dev/null; then
  printf '{\\rtf1\\ansi{\\fonttbl\\f0\\fnil .AppleSystemUIFont;}\\f0\\fs44 The notch, made useful.}' > "$TMP/Copy.rtf"
  open -a TextEdit "$TMP/Copy.rtf" --args -AppleLanguages '(en)' -AppleLocale en_US; sleep 2.5
  osascript -e 'tell application "System Events" to tell process "TextEdit"' \
    -e 'set frontmost to true' -e 'set position of front window to {160, 300}' -e 'set size of front window to {520, 170}' \
    -e 'end tell' -e 'delay 0.6' -e 'tell application "System Events" to keystroke "a" using command down' >/dev/null 2>&1
  sleep 1
  TEXTEDIT=$(swift - <<'SWIFT' 2>/dev/null
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "TextEdit" && (w["kCGWindowLayer"] as? Int) == 0 { print(w["kCGWindowNumber"]!); break }
SWIFT
)
  [ -n "$TEXTEDIT" ] && screencapture -x -o -l "$TEXTEDIT" "$OUT/textedit-copy.png" && echo "  textedit-copy"
  osascript -e 'tell application "System Events" to tell process "TextEdit" to set frontmost to true' -e 'tell application "System Events" to keystroke "q" using command down' >/dev/null 2>&1
fi
front() { osascript -e 'tell application "System Events" to set frontmost of process "Col" to true' >/dev/null 2>&1 || true; sleep 0.8; }
key() { osascript -e "tell application \"System Events\" to tell process \"Col\" to key code $1" >/dev/null 2>&1; }
# The welcome, step by step (Return moves on).
player; run -ColWelcome YES; sleep 5; front; shoot window welcome-discover
key 36; sleep 3; shoot window welcome-island
key 36; sleep 3; shoot window welcome-gestures
key 36; sleep 3; shoot window welcome-ready
for pane in appearance pages prompter aiApps; do player; run -ColSettings "$pane"; sleep 3; front; shoot window "settings-$pane"; done

echo "Website and README images:"
mkdir -p site/assets/island site/assets/app site/assets/film site/assets/macos docs/images
for s in rest music-compact lyrics-compact home-open airpods-pro airpods-max push-build agent-request claude-working agents-compact \
  live-agents ai-page ask prompter shelf-drop shelf-one clipboard tools size-compact size-large \
  glass-liquid glass-transparent glass-tinted glass-black; do
  cwebp -quiet -q 90 -alpha_q 100 -exact "$OUT/$s.png" -o "site/assets/island/$s.webp"
done
for s in welcome-discover welcome-island welcome-gestures welcome-ready settings-appearance settings-pages settings-prompter settings-aiApps; do
  cwebp -quiet -q 88 -alpha_q 100 "$OUT/$s.png" -o "site/assets/app/$s.webp"
done
# The films in H.264, each with its first useful frame as a poster.
swift scripts/encode-film.swift "$OUT/lyrics.mov" site/assets/film/lyrics.mp4 1296 1400000 >/dev/null
swift scripts/encode-film.swift "$OUT/prompter.mov" site/assets/film/prompter.mp4 1120 1600000 >/dev/null
poster() {
  swift - "$1" "$TMP/poster.png" "$2" <<'SWIFT' >/dev/null 2>&1
import AVFoundation
import AppKit
let a = CommandLine.arguments
let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: a[1])))
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let image = try! generator.copyCGImage(at: CMTime(seconds: Double(a[3])!, preferredTimescale: 600), actualTime: nil)
try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
SWIFT
  cwebp -quiet -q 86 "$TMP/poster.png" -o "$3"
}
poster site/assets/film/lyrics.mp4 0.2 site/assets/film/lyrics.webp
poster site/assets/film/prompter.mp4 2.5 site/assets/film/prompter.webp
# The pieces of macOS the scenes move around: the arrow cursor and the brief as it sits on a desktop.
cp "$TMP/cursor-arrow.png" site/assets/macos/cursor-arrow.png
cp "$TMP/brief-icon.png" site/assets/macos/brief-icon.png
[ -f "$OUT/textedit-copy.png" ] && cwebp -quiet -q 92 "$OUT/textedit-copy.png" -o site/assets/macos/textedit-copy.webp
# The desktop: whole for the MacBook, and its top 600 points at 2x for the close-ups and the scenes.
cwebp -quiet -q 84 -resize 1920 0 "$DESKTOP" -o site/assets/desktop.webp
cwebp -quiet -q 86 -crop 0 0 3024 1200 "$DESKTOP" -o site/assets/desktop-top.webp
cwebp -quiet -q 86 -crop 0 880 3024 1084 "$DESKTOP" -o site/assets/desktop-lake.webp
# The README cannot lay captures on the desktop with CSS: it gets them composed.
swift scripts/compose-site.swift "$DESKTOP" "$OUT" >/dev/null
for f in "$OUT"/figures/*.png; do cwebp -quiet -q 88 "$f" -o "docs/images/$(basename "$f" .png).webp"; done
echo "  site/assets/{island,app,film,macos}, site/assets/desktop*.webp, docs/images"

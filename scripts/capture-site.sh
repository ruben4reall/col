#!/bin/bash
# scripts/capture-site.sh: photographs and films the real app for the website, then lays the island on a real macOS
# desktop (COL_DESKTOP, a 3024 x 1964 PNG) and writes the WebP pictures and MP4 films the website and the README use.
# While the island is photographed, that same desktop covers the screen just under it, so its glass shows the website's
# desktop and nothing of the Mac the pictures are taken on.
# Nothing is drawn by hand: each picture is Col itself, in English, driven by its debug switches and its local API,
# with a silent demo track, demo files and original lyrics, so no sound and no personal data (calendar, clipboard,
# library) appear. The Col already running is quit first and opened again at the end.
# COL_PARTS takes again only some of it: island, drawers, films, textedit, welcome, settings, readme, gifs (all of them
# by default).
# Only the pictures taken in this run are written to site/ and docs/.
set -uo pipefail
cd "$(dirname "$0")/.."
BUILD="${COL_BUILD_DIR:-.build/xcode}"
[[ "$BUILD" = /* ]] || BUILD="$PWD/$BUILD"
# COL_CONFIGURATION=Release films the app as people get it: a debug build can take a second to draw a full drawer the
# first time, and the drawer would then appear without its drop.
CONFIGURATION="${COL_CONFIGURATION:-Debug}"
APP="$BUILD/Build/Products/$CONFIGURATION/Col.app"
DESKTOP="${COL_DESKTOP:?set COL_DESKTOP to a 3024 x 1964 PNG of a macOS desktop}"
OUT=.build/site-shots
TMP=$(mktemp -d)
touch "$TMP/start"
PARTS=" ${COL_PARTS:-island drawers films textedit welcome settings readme gifs} "
part() { [[ "$PARTS" == *" $1 "* ]]; }
mkdir -p "$OUT"
[ -d "$APP" ] || COL_BUILD_DIR="$BUILD" scripts/build.sh "$CONFIGURATION" >/dev/null
# A socket of its own: the captures never reach another copy.
export COL_SOCKET="$TMP/col.sock"
COLCTL="$APP/Contents/Helpers/colctl"
# The user's own copy (Col, or Islet before 2.0), quit now and opened again at the end.
USER_APP=$(ps -axo command= | grep -E -m1 "/(Col|Islet)\.app/Contents/MacOS/(Col|Islet)$" | grep -v "$APP" | sed -E 's|/Contents/MacOS/[^/]+$||' || true)
[ -n "$USER_APP" ] && osascript -e "tell application \"$USER_APP\" to quit" >/dev/null 2>&1 && sleep 2
SUPPORT="$HOME/Library/Application Support/Col"
SUPPORT_EXISTED=$([ -d "$SUPPORT" ] && echo 1 || echo 0)
LYRICS="$SUPPORT/Lyrics/Sunset Avenue - Golden Hour.lrc"
LYRICS_EXISTED=$([ -d "$SUPPORT/Lyrics" ] && echo 1 || echo 0)
# The demo widgets are saved where the user's own are: theirs are put back as they were.
WIDGETS="$SUPPORT/Widgets.json"
[ -f "$WIDGETS" ] && cp -p "$WIDGETS" "$TMP/Widgets.json"
PLAYER= BACKDROP=
# `swift script.swift` runs the script in a process of its own, which outlives the swift command: these stop the demo
# track and the desktop over the screen by their script's name.
stop_player() { pkill -f "scripts/fake-player.swift" 2>/dev/null; PLAYER=; }
stop_backdrop() { pkill -f "scripts/desktop-backdrop.swift" 2>/dev/null; BACKDROP=; }
# Whatever happens, the desktop over the screen and the demo track go, the lyrics, the widgets and any folder the
# captures made leave, and the user's copy comes back.
cleanup() {
  stop_player
  stop_backdrop
  pkill -f "$APP/Contents/MacOS/Col" 2>/dev/null
  sleep 1
  rm -f "$LYRICS"
  [ "$LYRICS_EXISTED" = 0 ] && rmdir "$SUPPORT/Lyrics" 2>/dev/null
  if [ -f "$TMP/Widgets.json" ]; then cp -p "$TMP/Widgets.json" "$WIDGETS"; else rm -f "$WIDGETS"; fi
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
# shoot <island|prompter|lock|desktop|window> <name>: the island hangs from the top of the screen, the prompter just
# above it, the Lock Screen's widgets at the screen saver's level, the lyrics on the desktop below every window;
# windows are the largest one at the normal level.
shoot() {
  local line id layer x y w h
  case "$1" in
    island) line=$(windows | awk '$2==27 && $4==0' | head -1) ;;
    prompter) line=$(windows | awk '$2==28 && $4==0' | head -1) ;;
    lock) line=$(windows | awk '$2==1000' | head -1) ;;
    desktop) line=$(windows | awk '$2<0' | head -1) ;;
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
# The pages of the open island: Home holds the stacks given, the others are the website's.
deck() {
  hex '{"pages":[{"id":"home","symbol":"house.fill","stacks":'"$1"'},{"id":"prompter","stacks":[{"widgets":["prompter"]}]},{"id":"ai","stacks":[{"widgets":["ai"]}]},{"id":"shelf","stacks":[{"widgets":["shelf"]}]},{"id":"clipboard","stacks":[{"widgets":["clipboard"]}]},{"id":"tools","stacks":[{"widgets":["tools"]}]}]}'
}
DECK=$(deck '[{"widgets":["music","clock"]},{"widgets":["lyrics","agenda"]}]')
SERVERS=$(hex '[{"id":"studio","name":"Mac Studio","kind":"ollama","address":"http://127.0.0.1:11434","usesToken":false},{"id":"lab","name":"Workstation","kind":"llamaCpp","address":"http://127.0.0.1:8080","usesToken":false}]')
# Liquid glass unless GLASS says otherwise, whatever the user chose; the demo pages (PAGES for others) and model servers.
run() {
  pkill -f "$APP/Contents/MacOS/Col" 2>/dev/null; sleep 0.6
  ("$APP/Contents/MacOS/Col" -AppleLanguages '(en)' -AppleLocale en_US -islandGlass "${GLASS:-liquid}" -pageDeck "<${PAGES:-$DECK}>" \
    -aiServers "<$SERVERS>" -askModel "studio
qwen3:8b" -showsLyricsInClosedIsland "${LYRICS_CLOSED:-NO}" -keepsClipboardHistory YES -ColWallpaper "$DESKTOP" \
    -ColMenuBarFree 132 "$@" >/dev/null 2>&1 &)
  for _ in {1..60}; do curl -s --unix-socket "$COL_SOCKET" http://col/v1/status >/dev/null 2>&1 && break; sleep 0.2; done
}
# The demo track, restarted before each capture of the player so every picture shows the same moment of the song.
player() {
  stop_player
  ALBUM="Long Light" swift scripts/fake-player.swift "Golden Hour" "Sunset Avenue" 214 "$TMP/cover.png" >/dev/null 2>&1 &
  PLAYER=$!
  sleep 3
}
post() { curl -s --unix-socket "$COL_SOCKET" -X POST "http://col/v1/agents/events?agent=$1" -d "$2" >/dev/null; }
pid() { pgrep -f "$APP/Contents/MacOS/Col" | head -1; }
backdrop() {
  stop_backdrop
  swift scripts/desktop-backdrop.swift "${BACKDROP_IMAGE:-$DESKTOP}" "$@" >/dev/null 2>&1 &
  BACKDROP=$!
  sleep 3
}
RECORDER="$TMP/record-film"
recorder() { [ -x "$RECORDER" ] || swiftc -O scripts/record-film.swift -o "$RECORDER" 2>/dev/null; }
# record <file> <seconds> <x> <y> <width> <height>: starts filming Col's windows and the desktop's, and returns once the
# recording runs, its process in RECORDING. Starting one can take ScreenCaptureKit a second or two; while macOS waits
# for someone to allow the screen recording, it never starts, and the capture stops there rather than wait forever.
record() {
  recorder
  rm -f "$TMP/recorder.out"
  "$RECORDER" "$1" "$2" "Col,$(pgrep -f desktop-backdrop | paste -sd, -)" "$3" "$4" "$5" "$6" >"$TMP/recorder.out" 2>&1 &
  RECORDING=$!
  for _ in {1..80}; do grep -q recording "$TMP/recorder.out" 2>/dev/null && return 0; sleep 0.1; done
  kill "$RECORDING" 2>/dev/null
  echo "The recording did not start: is the screen recording allowed in System Settings, Privacy & Security?" >&2
  exit 1
}
# click <x> <y>: a click at a point of the screen, in points from its top left corner.
click() {
  [ -x "$TMP/click" ] || swiftc -O - -o "$TMP/click" 2>/dev/null <<'SWIFT'
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let point = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(80_000)
}
SWIFT
  "$TMP/click" "$1" "$2"
}
film() { record "$OUT/$1.mov" "$2" "$3" 0 "$4" "$5"; wait "$RECORDING"; echo "  $1 (film)"; }
# still <name> <x> <y> <width> <height>: what the films see, as a picture: Col's windows and the desktop's, nothing else.
still() {
  record "$TMP/still.mov" 1.5 "$2" "$3" "$4" "$5"
  wait "$RECORDING"
  swift - "$TMP/still.mov" "$OUT/$1.png" <<'SWIFT' >/dev/null 2>&1
import AVFoundation
import AppKit
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let last = CMTimeSubtract(asset.duration, CMTime(value: 1, timescale: 60))
let image = try! generator.copyCGImage(at: last, actualTime: nil)
try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
SWIFT
  [ -f "$OUT/$1.png" ] && echo "  $1"
}
# The drawers hang over the menu bar: their desktop lies under them. macOS draws the drawers' own items in a menu bar of
# its own, which no capture of Col's windows holds, so the drawers' backdrop draws them where they are, on a desktop
# without the picture's battery, Wi-Fi and Spotlight icons, where the items go (COL_DRAWERS_DESKTOP, by default
# desktop-drawers.png beside COL_DESKTOP).
DRAWERS_DESKTOP="${COL_DRAWERS_DESKTOP:-${DESKTOP%.png}-drawers.png}"
[ -f "$DRAWERS_DESKTOP" ] || DRAWERS_DESKTOP="$DESKTOP"
DRAWERS=(-ColIntro NO -tidiesMenuBar YES -ColDrawersDemo YES -ColDrawersQuiet YES -ColDrawersBackdrop "$DRAWERS_DESKTOP")
# A drawer open over that desktop (0 is the first, all the All drawer): its window's "id x y width height", in points.
open_drawer() {
  BACKDROP_IMAGE="$DRAWERS_DESKTOP" backdrop 0 0
  run "${DRAWERS[@]}" -ColDrawersOpen "$1"; sleep 6
  windows | awk '$2==25' | sort -k5 -n -r | head -1 | awk '{print $1, $3, $4, $5, $6}'
}
# Widgets a home server, a washing machine and a build would push, for the Widgets place and Settings, Connect.
widgets() {
  echo '{"title":"Living room","value":21.5,"unit":"°C","symbol":"thermometer.medium","tint":"orange","lines":["Humidity 48%","Window closed"],"buttons":[{"title":"Heat","url":"http://homeassistant.local:8123/api/webhook/heat","symbol":"flame.fill"}]}' \
    | "$COLCTL" widget set living --json - >/dev/null
  "$COLCTL" widget set washer --title "Washing machine" --value 18 --unit "min left" --progress 70% --symbol washer.fill --tint blue --line "Cotton, 40°" >/dev/null
  "$COLCTL" widget set build --title "Release build" --value Passed --symbol checkmark.seal.fill --tint green --line "Col 3.0.0" --line "All tests passed" >/dev/null
}
# The agent's request stays until it is answered: the hook waits in the background, and goes once photographed.
ask() {
  (echo "$1" | "$COLCTL" hook >/dev/null 2>&1) &
  sleep 3; shoot island "$2"
  pkill -f "Helpers/colctl hook" 2>/dev/null
}

# Original lyrics, written for these pictures and timed word by word, read from the folder Col prefers to LRCLIB.
# The ten lines come round again until the end of the demo track, so every moment of it has a line being sung.
mkdir -p "$(dirname "$LYRICS")"
python3 - "$LYRICS" <<'PY'
import sys
lines = ["Streetlights waking one by one", "We drive into the golden hour", "Windows down and nowhere to be", "Into the blue",
         "Hold the light", "Before the city turns to blue", "Every song sounds like a summer", "Every road leads back to you",
         "Streetlights waking one by one", "We drive into the golden hour"]
times = [(26 * lap + 2.6 * i, text) for lap in range(8) for i, text in enumerate(lines)]
stamp = lambda t: "%02d:%05.2f" % (t // 60, t % 60)
out = []
for n, (start, text) in enumerate(times):
    end = times[n + 1][0] - 0.35 if n + 1 < len(times) else start + 2.3
    words = text.split(" ")
    weights = [len(w) + 2 for w in words]
    at, timed = start, []
    for word, weight in zip(words, weights):
        timed.append("<%s> %s" % (stamp(at), word))
        at += (end - start) * weight / sum(weights)
    out.append("[%s] %s <%s>" % (stamp(start), " ".join(timed), stamp(end)))
open(sys.argv[1], "w").write("\n".join(out) + "\n")
PY
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

if part island || part films; then
echo "Island:"
backdrop
fi
if part island; then
# At rest first, before the demo track: the island is the notch itself, its exact shape.
run; sleep 3; shoot island rest
# Before any music: a call about to start, the weather beside the clock (from Open-Meteo, for a city far from the Mac's
# own place), three accessories, widgets pushed by other programs, and what Col 3 brings.
run -ColDemo meeting; sleep 3; shoot island meeting-compact
run -ColDemo meeting -ColOpen YES -ColPage live; sleep 3; shoot island meeting-live
PLACE=$(hex '{"name":"Lausanne","detail":"Switzerland","latitude":46.5197,"longitude":6.6323}')
PAGES=$(deck '[{"widgets":["music","clock"]},{"widgets":["lyrics","weather"]}]') run -ColOpen YES -showsWeather YES -weatherPlace "<$PLACE>"
sleep 6; shoot island weather
PAGES=$(deck '[{"widgets":["devices"]},{"widgets":["clock"]}]') run -ColOpen YES -ColDemo devices -showsAccessoryBatteries YES
sleep 3; shoot island devices
PAGES=$(deck '[{"widgets":["widgets"]}]') run -ColOpen YES; sleep 1; widgets; sleep 2; shoot island widgets
# The card opens a moment after launch, once its tiles have come in.
run -ColDemo whatsnew
for _ in {1..20}; do windows | awk '$2==27 && $5>500' | grep -q . && break; sleep 0.2; done
sleep 0.8; shoot island whats-new
# A screen without a notch: the pill at rest.
run -ColNoNotch YES -floatingStyle pill; sleep 3; shoot island pill-rest
player; sleep 2
player; run; sleep 3; shoot island music-compact
# Col 3.1: when the menu bar leaves no room beside the notch, the activity goes beneath the camera.
player; run -activitiesBeneath YES; sleep 3; shoot island beneath-music
run -activitiesBeneath YES -ColDemo privacy; sleep 2; shoot island beneath-privacy
# A short line, whole in the wing, whatever room the menu bar leaves it.
player; LYRICS_CLOSED=YES run; sleep 4; shoot island lyrics-compact
player; run -ColOpen YES; sleep 3; shoot island home-open
# The lyrics, large, on the Lock Screen (shown on the desktop, with the weather), and on the desktop itself. The track
# starts again for each, so the picture falls in the middle of a line rather than while one glides to the next.
player; run -showsOnLockScreen YES -showsLyricsOnLockScreen YES -ColLockPreview YES -showsWeather YES -weatherPlace "<$PLACE>"
sleep 4.6; shoot lock lock-lyrics
player; run -showsLyricsOnDesktop YES; sleep 2; shoot desktop desktop-lyrics
# The three shapes of a screen without a notch: the pill, Col's own notch, the capsule below the menu bar.
run -ColNoNotch YES -floatingStyle pill; sleep 3; shoot island pill-music
run -ColNoNotch YES -floatingStyle pill -ColOpen YES; sleep 3; shoot island pill-open
run -ColNoNotch YES -floatingStyle notch; sleep 3; shoot island drawn-music
run -ColNoNotch YES -floatingStyle below; sleep 3; shoot island below-music
run -ColDemo headphones; sleep 3; shoot island airpods-pro
run -ColDemo max; sleep 3; shoot island airpods-max
run; sleep 1; "$COLCTL" push build --title Build --symbol hammer.fill --tint orange --progress 40% >/dev/null; sleep 2; shoot island push-build
# Agents: a request, a question and a plan first, then one at work, then four at once.
run -ColOpen YES -ColPage live; sleep 1
# In a background list the shell would give the hook an empty stdin: the pipe stays inside the subshell.
ask '{"session_id":"site","hook_event_name":"PermissionRequest","cwd":"/Users/me/col","tool_name":"Bash","tool_input":{"command":"git push origin main","description":"Push the release"}}' agent-request
run -ColOpen YES -ColPage live; sleep 1
ask '{"session_id":"q1","hook_event_name":"PermissionRequest","cwd":"/Users/me/col","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Ship the Linux packages in this release?","header":"Release","multiSelect":false,"options":[{"label":"Yes, as a preview","description":"Build the .deb and the tarballs for x86-64 and ARM64"},{"label":"Not yet","description":"Keep them on their branch for now"}]}]}}' agent-question
run -ColOpen YES -ColPage live; sleep 1
ask '{"session_id":"p1","hook_event_name":"PermissionRequest","cwd":"/Users/me/col","tool_name":"ExitPlanMode","tool_input":{"plan":"# Release notes for Col 3\n\n1. Gather what changed since 2.0 from `CHANGELOG.md`.\n2. Write one line per feature, in the words of the app.\n3. Add the Windows and Linux downloads, with their links.\n\nNothing is published until you say so."}}' agent-plan
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
# The tools, with a focus session under way.
run -ColOpen YES -ColPage tools -showsPomodoro YES -ColDemo pomodoro; sleep 3; shoot island tools
player; run -ColOpen YES -islandSize compact; sleep 3; shoot island size-compact
player; run -ColOpen YES -islandSize large; sleep 3; shoot island size-large
fi
# The prompter, rolling out of the notch: a picture, then a film.
# The prompter keeps out of screenshots and waits for a voice: for the pictures it shows itself and rolls on its own.
PROMPTER=(-prompter.hiddenFromCapture NO -prompter.scrollMode auto)
SCRIPT="Good morning, everyone. Today we are introducing Col, the notch, made useful. It lives right under your camera, so your eyes stay on the people you talk to. Your script rolls at the pace of your voice, and waits whenever you stop. Nobody watching ever sees it: it stays out of your screenshots, your recordings and your calls."
if part island; then
run -ColPrompt "$SCRIPT" -ColPromptTitle "Launch video" "${PROMPTER[@]}"; sleep 4.5; shoot prompter prompter
fi
if part films; then
run -ColPrompt "$SCRIPT" -ColPromptTitle "Launch video" "${PROMPTER[@]}"; film prompter 11 476 560 210
# The lyrics following the song, the island open on Home.
player; run -ColOpen YES; film lyrics 11 432 648 228
fi
if part island; then
# The four kinds of glass, over the lake and its rocks (the desktop raised by 440 points), where the glass has
# something to bend: the website shows them on the same part of the desktop.
backdrop 440
for glass in liquid transparent tinted off; do
  name=$glass; [ "$glass" = off ] && name=black
  player; GLASS=$glass run -ColOpen YES; sleep 3; shoot island "glass-$name"
done
fi
stop_backdrop

echo "Windows:"
# Where a copy comes from, for the clipboard scene: a real TextEdit window with its text selected. Only when TextEdit
# is not already open, so the user's documents are never touched.
if part textedit && ! pgrep -x TextEdit >/dev/null; then
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
if part welcome; then
# The welcome, step by step (Return moves on).
player; run -ColWelcome YES; sleep 5; front; shoot window welcome-discover
key 36; sleep 3; shoot window welcome-island
key 36; sleep 3; shoot window welcome-gestures
key 36; sleep 3; shoot window welcome-ready
fi
if part settings; then
for pane in appearance pages prompter aiApps; do player; run -ColSettings "$pane"; sleep 3; front; shoot window "settings-$pane"; done
# Connect, with the widgets pushed to the island listed.
run -ColSettings connect; sleep 1; widgets; sleep 2; front; shoot window settings-connect
fi

if part gifs; then
# Col 3.2, the README's films: the recording starts first, Col opens into it, plays its intro (without its chime),
# the demo song comes beside the camera, the island opens on it, then closes (-ColFilm). On a MacBook with a notch
# (Col's own drawn notch, in the notch's place), and on a Mac without one (the pill in the menu bar). Then the drawers.
echo "README films:"
[ -n "$BACKDROP" ] || backdrop
recorder
SCREEN_W=$(swift -e 'import AppKit; print(Int(NSScreen.main!.frame.width))' 2>/dev/null || echo 1512)
take() {   # take <name> <seconds> <x> <width> <height> <Col's switches…>
  local name=$1 seconds=$2 x=$3 width=$4 height=$5
  shift 5
  pkill -f "$APP/Contents/MacOS/Col" 2>/dev/null; sleep 0.8
  # Col opens 1.2 seconds into the film (run waits 0.6 of them), once the recording runs.
  record "$OUT/$name.mov" "$seconds" "$x" 0 "$width" "$height"
  local recorder=$RECORDING
  sleep 0.6
  run "$@"
  # What happens in the film once Col runs, when DURING names it.
  local during=
  if [ -n "${DURING:-}" ]; then "$DURING" & during=$!; fi
  wait $recorder
  [ -n "$during" ] && wait $during
  echo "  $name (film)"
}
player; take readme-notch 13 $(( SCREEN_W / 2 - 400 )) 800 280 -ColIntro YES -playsIntroSound NO -ColFilm YES -ColNoNotch YES -floatingStyle notch
player; take readme-pill 13 $(( SCREEN_W / 2 - 400 )) 800 280 -ColIntro YES -playsIntroSound NO -ColFilm YES -ColNoNotch YES -floatingStyle pill
# The drawers, as people use them: a click on the first drawer's icon drops it, its apps arriving one after the other,
# and a click on its neck sends it back. It is opened once first, to find its icon and frame it, wherever the menu bar
# puts it. No song for this one.
stop_player
read -r _ dx _ dw _ <<< "$(open_drawer 0)"
if [ -n "${dw:-}" ]; then
  icon=$(( dx + dw / 2 ))
  fx=$(( icon - 380 )); fx=$(( fx < 0 ? 0 : (fx > SCREEN_W - 760 ? SCREEN_W - 760 : fx) ))
  drop() { sleep 2.4; click "$icon" 16; sleep 3.4; click "$icon" 16; }
  DURING=drop take readme-drawers 9.5 $fx 760 330 "${DRAWERS[@]}"
else
  echo "  readme-drawers: no drawer"
fi
fi

if part drawers; then
# The menu bar's drawers, in demo mode (generic icons, nothing of this Mac's menu bar): the All drawer dropped from its
# icon, alone for the website, which lays it on its own desktop, and with the desktop and the menu bar for the README.
read -r did dx dy dw dh <<< "$(open_drawer all)"
if [ -n "${did:-}" ]; then
  screencapture -x -o -l "$did" "$OUT/drawers.png" && echo "  drawers"
  still drawers-desktop "$dx" 0 "$dw" "$dh"
else
  echo "  drawers: no window"
fi
fi

echo "Website and README images:"
mkdir -p site/assets/island site/assets/app site/assets/film site/assets/macos docs/images
# Only what this run photographed.
taken() { [ "$OUT/$1.png" -nt "$TMP/start" ]; }
for s in rest music-compact beneath-music beneath-privacy lyrics-compact home-open airpods-pro airpods-max push-build agent-request claude-working agents-compact \
  live-agents ai-page ask prompter shelf-drop shelf-one clipboard tools size-compact size-large \
  glass-liquid glass-transparent glass-tinted glass-black meeting-compact meeting-live weather devices widgets whats-new \
  pill-rest pill-music pill-open drawn-music below-music agent-question agent-plan lock-lyrics desktop-lyrics; do
  taken "$s" && cwebp -quiet -q 90 -alpha_q 100 -exact "$OUT/$s.png" -o "site/assets/island/$s.webp"
done
mkdir -p site/assets/menubar
taken drawers && cwebp -quiet -q 90 -alpha_q 100 -exact "$OUT/drawers.png" -o site/assets/menubar/drawers.webp
taken drawers-desktop && cwebp -quiet -q 88 "$OUT/drawers-desktop.png" -o docs/images/drawers.webp
for s in welcome-discover welcome-island welcome-gestures welcome-ready settings-appearance settings-pages settings-prompter settings-aiApps \
  settings-connect; do
  taken "$s" && cwebp -quiet -q 88 -alpha_q 100 "$OUT/$s.png" -o "site/assets/app/$s.webp"
done
# The films in H.264, each with its first useful frame as a poster.
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
if part films; then
  swift scripts/encode-film.swift "$OUT/lyrics.mov" site/assets/film/lyrics.mp4 1296 1400000 >/dev/null
  swift scripts/encode-film.swift "$OUT/prompter.mov" site/assets/film/prompter.mp4 1120 1600000 >/dev/null
  poster site/assets/film/lyrics.mp4 0.2 site/assets/film/lyrics.webp
  poster site/assets/film/prompter.mp4 6 site/assets/film/prompter.webp
fi
# The pieces of macOS the scenes move around: the arrow cursor and the brief as it sits on a desktop.
cp "$TMP/cursor-arrow.png" site/assets/macos/cursor-arrow.png
cp "$TMP/brief-icon.png" site/assets/macos/brief-icon.png
taken textedit-copy && cwebp -quiet -q 92 "$OUT/textedit-copy.png" -o site/assets/macos/textedit-copy.webp
# The desktop: whole for the MacBook, and its top 600 points at 2x for the close-ups and the scenes.
cwebp -quiet -q 84 -resize 1920 0 "$DESKTOP" -o site/assets/desktop.webp
cwebp -quiet -q 86 -crop 0 0 3024 1200 "$DESKTOP" -o site/assets/desktop-top.webp
cwebp -quiet -q 86 -crop 0 880 3024 1084 "$DESKTOP" -o site/assets/desktop-lake.webp
# The README cannot lay captures on the desktop with CSS: it gets them composed.
if part readme; then
  swift scripts/compose-site.swift "$DESKTOP" "$OUT" >/dev/null
  for f in "$OUT"/figures/*.png; do cwebp -quiet -q 88 "$f" -o "docs/images/$(basename "$f" .png).webp"; done
fi
echo "  site/assets/{island,app,film,macos}, site/assets/desktop*.webp$(part readme && echo ', docs/images')"

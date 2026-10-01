#!/bin/bash
# scripts/capture-site.sh: photographs the real app for the website, window by window, then lays the island on a
# real macOS desktop (COL_DESKTOP, a 3024 x 1964 PNG) and writes the WebP files the website uses.
# While the island is photographed, that same desktop covers the screen just under it, so its glass shows the website's
# desktop and nothing of the Mac the pictures are taken on.
# Nothing is drawn by hand: each picture is Col itself, in English, driven by its debug switches, with a silent
# demo track playing so no sound and no personal data (calendar, clipboard) appear.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${COL_BUILD_DIR:-.build/xcode}/Build/Products/Debug/Col.app"
DESKTOP="${COL_DESKTOP:?set COL_DESKTOP to a 3024 x 1964 PNG of a macOS desktop}"
# The user's own Col, relaunched at the end if it was running.
USER_COL=$(ps -axo command= | grep -m1 "/Col.app/Contents/MacOS/Col$" | sed 's|/Contents/MacOS/Col$||' || true)
OUT=.build/site-shots
TMP=$(mktemp -d)
mkdir -p "$OUT"
# Whatever happens, the desktop over the screen and the demo track go, and the user's Col comes back.
PLAYER= BACKDROP=
trap 'kill $PLAYER $BACKDROP 2>/dev/null; pkill -x Col 2>/dev/null; rm -rf "$TMP"; [ -n "$USER_COL" ] && open "$USER_COL"' EXIT
[ -d "$APP" ] || scripts/build.sh >/dev/null

# The window of Col whose frame matches, "panel" (the island, hanging from the top of the screen) or "window": its
# number, then its frame in points, "id x y width height". With "clear", it prints nothing but waits (up to a minute)
# until no other app's window lies over the island's frame: the screen capture of the glass must be the island alone.
window_info() {
  swift - "$@" <<'SWIFT' 2>/dev/null
import CoreGraphics
import Foundation
let kind = CommandLine.arguments[1]
func windows() -> [[String: Any]] { CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]] }
func frame(_ w: [String: Any]) -> CGRect {
    let b = w["kCGWindowBounds"] as! [String: Double]
    return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
}
let system: Set<String> = ["Col", "Control Center", "Centre de contrôle", "Window Server", "SystemUIServer", "Dock"]
if kind == "clear" {
    let rect = CGRect(x: Double(CommandLine.arguments[2])!, y: 0, width: Double(CommandLine.arguments[3])!, height: Double(CommandLine.arguments[4])!)
    for _ in 0..<60 {
        let over = windows().contains { w in
            (w["kCGWindowLayer"] as? Int ?? 0) > 27 && !system.contains(w["kCGWindowOwnerName"] as? String ?? "") && frame(w).intersects(rect)
        }
        if !over { break }
        Thread.sleep(forTimeInterval: 1)
    }
} else {
    for w in windows() where (w["kCGWindowOwnerName"] as? String) == "Col" {
        let f = frame(w)
        if (kind == "panel") == (f.minY == 0) { print(w["kCGWindowNumber"]!, Int(f.minX), Int(f.minY), Int(f.width), Int(f.height)); break }
    }
}
SWIFT
}
shoot() {
  local info id x y w h
  info=$(window_info "$1"); [ -n "$info" ] || return 0
  read -r id x y w h <<< "$info"
  screencapture -x -o -l "$id" "$OUT/$2.png"
  # The island: what shows through its glass comes from the screen, where the website's desktop lies under it.
  if [ "$1" = panel ]; then
    window_info clear "$x" "$w" "$h"
    screencapture -x -R "$x,$y,$w,$h" "$TMP/screen.png"
    swift scripts/glass-merge.swift "$OUT/$2.png" "$TMP/screen.png"
  fi
  echo "  $2"
}
# Liquid glass unless GLASS says otherwise, whatever the user chose.
run() { pkill -x Col 2>/dev/null || true; sleep 0.6; ("$APP/Contents/MacOS/Col" -AppleLanguages '(en)' -AppleLocale en_US -islandGlass "${GLASS:-liquid}" "$@" >/dev/null 2>&1 &) }

echo "Island:"
swift scripts/desktop-backdrop.swift "$DESKTOP" >/dev/null 2>&1 &
BACKDROP=$!
sleep 3
# At rest first, before the demo track: the island is the notch itself, its exact shape.
run; sleep 4; shoot panel rest

swift brand/scripts/demo-cover.swift "$TMP/cover.png"
# Demo files for the shelf (a brief, a photo, a note), and the pieces of macOS the website's scenes use.
swift brand/scripts/demo-files.swift "$TMP/files" "$TMP/cover.png" >/dev/null
mkdir -p "$TMP/none" "$TMP/one"
cp "$TMP/files/Brief.pdf" "$TMP/one/"
# The demo track, restarted before each capture of the player so every picture shows the same moment of the song.
PLAYER=
player() {
  [ -n "$PLAYER" ] && kill "$PLAYER" 2>/dev/null
  ALBUM="Long Light" swift scripts/fake-player.swift "Golden Hour" "Sunset Avenue" 214 "$TMP/cover.png" >/dev/null 2>&1 &
  PLAYER=$!
  sleep 3
}
player
sleep 4
player; run; sleep 4; shoot panel music-compact
player; run -ColOpen YES; sleep 4; shoot panel music-open
run -ColDemo headphones; sleep 7; shoot panel airpods-pro
run -ColDemo max; sleep 7; shoot panel airpods-max
run -ColOpen YES -ColPage live; sleep 3
# In a background list the shell would give the hook an empty stdin: the pipe stays inside the subshell.
(echo '{"session_id":"site","hook_event_name":"PermissionRequest","cwd":"/Users/me/col","tool_name":"Bash","tool_input":{"command":"git push origin main","description":"Push the release"}}' \
  | "$APP/Contents/Helpers/colctl" hook >/dev/null 2>&1) &
sleep 3; shoot panel agent-request
pkill -f "Helpers/colctl hook" 2>/dev/null || true
# GitHub Copilot in VS Code: a session running a command, as VS Code's own hooks report it (Col only watches).
run -ColOpen YES -ColPage live; sleep 3
for event in '"hook_event_name":"SessionStart","source":"new"' '"hook_event_name":"UserPromptSubmit","prompt":"Fix the test"' \
  '"hook_event_name":"PreToolUse","tool_name":"run_in_terminal","tool_input":{"command":"swift test"},"tool_use_id":"t1"'; do
  echo "{\"session_id\":\"site\",\"transcript_path\":\"/tmp/site.json\",\"cwd\":\"/Users/me/col\",$event}" \
    | "$APP/Contents/Helpers/colctl" hook --agent copilot >/dev/null 2>&1
done
sleep 2; shoot panel agent-copilot
# The shelf: files dragged over, one dropped, then three. Demo files only: the user's shelf is never read.
run -ColDemoShelf "$TMP/none" -ColDemo drop -ColOpen YES -ColPage shelf; sleep 4; shoot panel shelf-drop
run -ColDemoShelf "$TMP/one" -ColOpen YES -ColPage shelf; sleep 4; shoot panel shelf-one
run -ColDemoShelf "$TMP/files" -ColOpen YES -ColPage shelf; sleep 4; shoot panel shelf-files
# The clipboard, with demo copies: the real pasteboard is never read.
run -ColDemo clipboard -ColDemoImage "$TMP/cover.png" -ColOpen YES -ColPage clipboard; sleep 4; shoot panel clipboard
# Settings made visible: every page off, then the three sizes of the open island.
player; run -ColOpen YES -enabledPages '()'; sleep 4; shoot panel music-open-minimal
player; run -ColOpen YES -islandSize compact; sleep 4; shoot panel music-open-compact
player; run -ColOpen YES -islandSize large; sleep 4; shoot panel music-open-large
kill "$BACKDROP" 2>/dev/null || true
# The four kinds of glass, over the lake and its rocks (the desktop raised by 440 points), where the glass has
# something to bend: the website shows them on the same part of the desktop.
swift scripts/desktop-backdrop.swift "$DESKTOP" 440 >/dev/null 2>&1 &
BACKDROP=$!
sleep 3
for glass in liquid transparent tinted off; do
  name=$glass; [ "$glass" = off ] && name=black
  player; GLASS=$glass run -ColOpen YES; sleep 4; shoot panel "glass-$name"
done
kill "$BACKDROP" 2>/dev/null || true

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
for pane in general island activities; do run -ColSettings "$pane"; sleep 3; front; shoot window "settings-$pane"; done
# The Pages section, with System on, then off.
run -ColSettings island -ColSettingsHeight 900; sleep 3; front; shoot window settings-pages-on
run -ColSettings island -ColSettingsHeight 900 -enabledPages '()'; sleep 3; front; shoot window settings-pages-off

echo "Website and README images:"
mkdir -p site/assets/island site/assets/app docs/images
for s in rest music-compact music-open airpods-pro airpods-max agent-request agent-copilot shelf-drop shelf-one shelf-files clipboard \
  music-open-minimal music-open-compact music-open-large glass-liquid glass-transparent glass-tinted glass-black; do cwebp -quiet -q 90 -alpha_q 100 "$OUT/$s.png" -o "site/assets/island/$s.webp"; done
for s in settings-general settings-island settings-activities settings-pages-on settings-pages-off; do cwebp -quiet -q 88 "$OUT/$s.png" -o "site/assets/app/$s.webp"; done
# The pieces of macOS the scenes move around: the arrow cursor and the brief as it sits on a desktop.
mkdir -p site/assets/macos
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
echo "  site/assets/{island,app}, site/assets/desktop*.webp, docs/images"

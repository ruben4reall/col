#!/bin/sh
# The real app, end to end, under a headless Sway with a private D-Bus session and a virtual pointer: hidden at rest,
# the top edge brings it out, a rest opens it, it leaves with the pointer; colctl pushes an activity; an agent's
# permission request opens the island, a click on Allow answers the hook as Claude Code expects.
#
#   tools/e2e.sh BUILD_DIR OUT_DIR
#
# Needs sway, grim, python3, a C compiler and wayland-scanner. Run it inside `dbus-run-session`.
set -eu

build=$(realpath "$1")
out=$2
mkdir -p "$out"
out=$(realpath "$out")
here=$(cd "$(dirname "$0")" && pwd)
col="$build/src/app/col-island"
colctl="$build/src/colctl/colctl"

run=$(mktemp -d)
chmod 700 "$run"
pids=""
cleanup() {
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
    exec 3>&- 2>/dev/null || true
    rm -rf "$run"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    [ -f "$run/col.log" ] && cat "$run/col.log" >&2
    exit 1
}

# The virtual pointer.
wayland-scanner client-header "$here/wlr-virtual-pointer-unstable-v1.xml" "$run/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$here/wlr-virtual-pointer-unstable-v1.xml" "$run/virtual-pointer.c"
cc -O1 -o "$run/pointer" "$here/pointer.c" "$run/virtual-pointer.c" -I"$run" $(pkg-config --cflags --libs wayland-client)

export XDG_RUNTIME_DIR="$run"
export XDG_CONFIG_HOME="$run/config" XDG_CACHE_HOME="$run/cache" XDG_DATA_HOME="$run/data" HOME="$run/home"
mkdir -p "$XDG_CONFIG_HOME/col" "$HOME"
# A first run that already said hello, so no settings window covers the screen.
printf '{"welcome-shown": true}\n' >"$XDG_CONFIG_HOME/col/settings.json"

width=1600
height=900
python3 -I "$here/backdrop.py" "$run/backdrop.png" "$width" "$height"
printf 'output HEADLESS-1 resolution %sx%s scale 1 bg %s fill\ndefault_border none\n' "$width" "$height" "$run/backdrop.png" >"$run/sway.conf"
unset DISPLAY WAYLAND_DISPLAY
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER="${WLR_RENDERER:-pixman}"
sway -c "$run/sway.conf" >"$run/sway.log" 2>&1 &
pids="$pids $!"
socket=""
for _ in $(seq 100); do
    socket=$(find "$run" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' | head -n 1)
    [ -n "$socket" ] && break
    sleep 0.1
done
[ -n "$socket" ] || fail "sway did not start"
export WAYLAND_DISPLAY=$(basename "$socket")
sleep 0.5

# A sound server with a silent output, when PulseAudio is installed, for the volume.
sound=""
if command -v pulseaudio >/dev/null && command -v pactl >/dev/null; then
    pulseaudio -n --daemonize=no --exit-idle-time=-1 --load=module-native-protocol-unix --load=module-null-sink \
        >"$run/pulse.log" 2>&1 &
    pids="$pids $!"
    for _ in $(seq 50); do
        pactl info >/dev/null 2>&1 && { sound=yes; break; }
        sleep 0.1
    done
fi

mkfifo "$run/pointer.in"
"$run/pointer" "$width" "$height" <"$run/pointer.in" >"$run/pointer.out" 2>&1 &
pids="$pids $!"
exec 3>"$run/pointer.in"
pointer() {
    echo "$*" >&3
    sleep 0.15
}
# Out of the way before Col starts.
pointer move 800 700

"$col" >"$run/col.log" 2>&1 &
pids="$pids $!"
for _ in $(seq 100); do
    [ -S "$run/col/col.sock" ] && break
    sleep 0.1
done
[ -S "$run/col/col.sock" ] || fail "Col did not open its socket"
[ "$(stat -c %a "$run/col/col.sock")" = 600 ] || fail "the socket is not 0600"
[ "$(stat -c %a "$run/col")" = 700 ] || fail "the socket's folder is not 0700"
sleep 1

# The colour at a point of the screen: black is the island, blue the desktop. The points checked are inside the
# island but away from its content: the top of the capsule, the left margin of the open island.
pixel() {
    grim -t ppm - | python3 -I -c '
import sys
data = sys.stdin.buffer.read()
parts = data.split(b"\n", 3)
width = int(parts[1].split()[0])
pixels = parts[3]
x, y = int(sys.argv[1]), int(sys.argv[2])
r, g, b = pixels[(y * width + x) * 3:(y * width + x) * 3 + 3]
print("island" if max(r, g, b) < 24 else "desktop")
' "$1" "$2"
}
expect() {
    got=$(pixel "$1" "$2")
    [ "$got" = "$3" ] || { grim "$out/e2e-failed.png"; fail "$4: expected the $3 at $1,$2, saw the $got"; }
}
shot() {
    grim -g "420,0 760x290" "$out/$1.png"
}

"$colctl" status | grep -q "is running" || fail "colctl status"

# Hidden at rest: the desktop shows at the top.
expect 770 10 desktop "at rest"
shot e2e-rest

# The top edge brings it out; a rest opens it; leaving closes it.
pointer move 800 1
sleep 0.4
expect 770 10 island "peek from the top edge"
shot e2e-peek
sleep 1.2
expect 568 120 island "a rest opens it"
shot e2e-open
pointer move 800 700
sleep 1.2
expect 770 10 desktop "it leaves with the pointer"

# A script's activity shows in the closed island.
"$colctl" push build --title Build --symbol hammer --tint orange --progress 40%
sleep 0.8
expect 770 10 island "an activity"
shot e2e-activity
"$colctl" list | grep -q "build  Build  40%" || fail "colctl list"
"$colctl" remove build
sleep 1
expect 770 10 desktop "an activity removed"

# An agent asks: the island opens with Allow and Deny, at the left of the card's last row; a click answers the hook.
answer() {
    printf '%s' '{"session_id":"e2e","hook_event_name":"PermissionRequest","cwd":"/home/you/col","tool_name":"Bash","tool_input":{"command":"make release"}}' \
        | "$colctl" hook >"$run/hook.out" &
    hook=$!
    sleep 1.2
    expect 568 120 island "a request opens the island"
    shot "e2e-permission-$1"
    pointer move "$2" 155
    pointer click
    for _ in $(seq 30); do
        kill -0 "$hook" 2>/dev/null || break
        sleep 0.1
    done
    kill -0 "$hook" 2>/dev/null && fail "the hook still waits after $1"
    grep -q "\"behavior\":\"$1\"" "$run/hook.out" || fail "the hook printed: $(cat "$run/hook.out")"
    pointer move 800 700
    sleep 1.2
}
answer allow 627
answer deny 705

# Answered, the session works on in the closed island, and leaves with the session.
expect 770 10 island "the session at work"
shot e2e-working
printf '%s' '{"session_id":"e2e","hook_event_name":"SessionEnd"}' | "$colctl" hook
sleep 1
expect 770 10 desktop "the session ended"

# The clipboard: a copy made elsewhere lands in the history, on the tools page (when wl-clipboard is installed).
if command -v wl-copy >/dev/null; then
    printf 'copied for Col, %s' "$(date +%s)" | wl-copy
    sleep 0.5
    pointer move 800 1
    sleep 1.6
    pointer move 668 31
    pointer click
    sleep 0.6
    shot e2e-clipboard
    pointer move 800 700
    sleep 1.2
else
    echo "wl-clipboard missing: the clipboard is not photographed"
fi

# The volume: a change of the output's volume shows its gauge, and only a change.
if [ -n "$sound" ]; then
    expect 770 10 desktop "no gauge without a change"
    pactl set-sink-volume @DEFAULT_SINK@ 40%
    sleep 0.5
    expect 770 10 island "the volume changed"
    shot e2e-volume
    sleep 2
    expect 770 10 desktop "the gauge leaves"
else
    echo "PulseAudio missing: the volume is not checked"
fi

# Music: a player on the bus shows in the closed island; open, the player, and its lyrics when LRCLIB answers. The
# player says its position is 0, as some do: the island counts from where it started.
if python3 -c "import gi" 2>/dev/null; then
    python3 -I "$here/backdrop.py" "$run/cover.png" 300 300
    python3 -I "$here/fake-player.py" --zero-position --start 75 --art "$run/cover.png" >"$run/player.log" 2>&1 &
    player=$!
    pids="$pids $player"
    sleep 2.5
    expect 770 10 island "a song playing"
    shot e2e-music-closed
    pointer move 800 1
    sleep 1.8
    shot e2e-music-open
    if ls "$XDG_CACHE_HOME/col/lyrics/"*.json >/dev/null 2>&1; then
        echo "lyrics: looked up and kept in $XDG_CACHE_HOME/col/lyrics"
    else
        echo "warning: no lyrics kept, LRCLIB may be out of reach"
    fi
    ls "$XDG_CACHE_HOME/col/art" >/dev/null 2>&1 && echo "warning: a file:// cover was copied to the cache"
    pointer move 800 700
    sleep 1.2
    kill "$player"
    sleep 1
else
    echo "python3-gi missing: the music is not checked"
fi

"$col" --quit
sleep 0.5
grep -iE "critical" "$run/col.log" && fail "criticals in the log"
echo "e2e: all good"

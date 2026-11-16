#!/bin/sh
# Photographs the island in each of its demo states, under a headless Sway, with grim.
#
#   tools/screenshots.sh BUILD/src/app/col-island OUT_DIR [SCALE] [STATES...]
#
# Needs sway, grim, swaybg and python3. Nothing of the user's is touched: the session, its settings and its caches live
# in a folder of their own, removed at the end.
set -eu

col=$(realpath "$1")
out=$2
scale=${3:-1}
shift 2
[ $# -gt 0 ] && shift
states=${*:-"collapsed peek music-closed music lyrics lyrics-closed agent agent-permission volume timer tools battery settings"}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
out=$(realpath "$out")

run=$(mktemp -d)
chmod 700 "$run"
sway_pid=""
cleanup() {
    [ -n "$sway_pid" ] && kill "$sway_pid" 2>/dev/null || true
    rm -rf "$run"
}
trap cleanup EXIT

export XDG_RUNTIME_DIR="$run"
export XDG_CONFIG_HOME="$run/config" XDG_CACHE_HOME="$run/cache" XDG_DATA_HOME="$run/data" HOME="$run/home"
mkdir -p "$XDG_CONFIG_HOME/gtk-4.0" "$HOME"
# The font most desktops use for their interface today, when it is installed.
if fc-list 2>/dev/null | grep -qi "Inter"; then
    printf '[Settings]\ngtk-font-name=Inter 11\n' >"$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
fi

width=1600
height=900
python3 -I "$here/backdrop.py" "$run/backdrop.png" "$width" "$height"
cat >"$run/sway.conf" <<EOF
output HEADLESS-1 resolution ${width}x${height} scale $scale bg $run/backdrop.png fill
default_border none
EOF

unset DISPLAY WAYLAND_DISPLAY
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER="${WLR_RENDERER:-pixman}"
sway -c "$run/sway.conf" >"$run/sway.log" 2>&1 &
sway_pid=$!
for _ in $(seq 100); do
    socket=$(find "$run" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' | head -n 1)
    [ -n "$socket" ] && break
    sleep 0.1
done
[ -n "$socket" ] || { cat "$run/sway.log"; echo "sway did not start" >&2; exit 1; }
export WAYLAND_DISPLAY=$(basename "$socket")
sleep 1

# The top of the screen, around its centre, in logical pixels.
crop_w=760
crop_h=290
crop="$(( (width / scale - crop_w) / 2 )),0 ${crop_w}x${crop_h}"
suffix=""
[ "$scale" != 1 ] && suffix="@${scale}x"

for state in $states; do
    "$col" --demo "$state" >"$run/$state.log" 2>&1 &
    pid=$!
    sleep 2.5
    if [ "$state" = settings ]; then
        grim "$out/$state$suffix.png"
    else
        grim -g "$crop" "$out/$state$suffix.png"
    fi
    [ "$state" = lyrics ] && grim "$out/desktop$suffix.png"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    if grep -qiE "critical|error" "$run/$state.log"; then
        echo "--- $state" >&2
        cat "$run/$state.log" >&2
    fi
done
echo "screenshots in $out"

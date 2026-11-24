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
# Whatever happens, the processes started here stop and their folder goes, and the script keeps its own result: a
# process that already left, or a file a dying one still holds, is not a failure of the check. GTK may start the
# document portal, which mounts a folder in the runtime directory: it is unmounted first.
cleanup() {
    status=$?
    set +e
    if [ -n "$sway_pid" ]; then
        kill "$sway_pid" 2>/dev/null
        wait "$sway_pid" 2>/dev/null
    fi
    for tool in fusermount3 fusermount; do
        command -v "$tool" >/dev/null && "$tool" -uz "$run/doc" 2>/dev/null
    done
    rm -rf "$run" 2>/dev/null
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

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
# The README's film, with COL_FILM=1: the intro, a song in the closed island, the island open on its lyrics, closed
# again, about twenty frames a second around the island (scripts/make-readme-gifs.sh turns the frames into a GIF).
if [ "${COL_FILM:-}" = 1 ] && [ "$scale" = 1 ]; then
    mkdir -p "$out/film-showcase"
    "$col" --demo showcase >"$run/showcase.log" 2>&1 &
    pid=$!
    sleep 2
    python3 -I - "$out/film-showcase" "$crop" 12.5 0.05 <<'PY'
import os, subprocess, sys, time
folder, crop, seconds, interval = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
start = time.monotonic()
index = 0
stamps = []
while time.monotonic() - start < seconds:
    taken = time.monotonic() - start
    subprocess.run(["grim", "-l", "1", "-g", crop, os.path.join(folder, "frame-%04d.png" % index)], check=False)
    stamps.append("%.3f" % taken)
    index += 1
    wait = start + index * interval - time.monotonic()
    if wait > 0:
        time.sleep(wait)
with open(os.path.join(folder, "times.txt"), "w") as times:
    times.write("\n".join(stamps) + "\n")
print("showcase film: %d frames" % index)
PY
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
fi
echo "screenshots in $out"

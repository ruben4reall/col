#!/bin/sh
# Col at rest, measured: after the first seconds, nothing happening for a while, how much memory it holds (RSS, and
# the part of it that is its own, PSS) and how much processor time it takes, and how often it wakes up.
#
#   tools/measure.sh BUILD_DIR [SECONDS]
#
# Runs the real app (not a demo) under a headless Sway with a private D-Bus session. Run it inside dbus-run-session.
set -eu

build=$(realpath "$1")
seconds=${2:-60}
here=$(cd "$(dirname "$0")" && pwd)

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
mkdir -p "$XDG_CONFIG_HOME/col" "$HOME"
printf '{"welcome-shown": true}\n' >"$XDG_CONFIG_HOME/col/settings.json"
printf 'output HEADLESS-1 resolution 1600x900 scale 1\n' >"$run/sway.conf"
unset DISPLAY WAYLAND_DISPLAY
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER="${WLR_RENDERER:-pixman}"
sway -c "$run/sway.conf" >"$run/sway.log" 2>&1 &
sway_pid=$!
sleep 1.5
export WAYLAND_DISPLAY=$(basename "$(find "$run" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' | head -n 1)")

"$build/src/app/col-island" >"$run/col.log" 2>&1 &
pid=$!
sleep 10

ticks=$(getconf CLK_TCK)
cpu() { awk '{print $14 + $15}' "/proc/$pid/stat"; }
wakeups() { awk '/^voluntary_ctxt_switches|^nonvoluntary_ctxt_switches/ {n += $2} END {print n}' "/proc/$pid/status"; }
cpu0=$(cpu)
wake0=$(wakeups)
sleep "$seconds"
cpu1=$(cpu)
wake1=$(wakeups)
rss=$(awk '/^VmRSS/ {print $2}' "/proc/$pid/status")
pss=$(awk '/^Pss:/ {print $2}' "/proc/$pid/smaps_rollup" 2>/dev/null || echo "?")
threads=$(awk '/^Threads/ {print $2}' "/proc/$pid/status")
echo "after ${seconds}s at rest:"
echo "  memory: RSS $((rss / 1024)) MB, PSS ${pss} kB"
awk -v a="$cpu0" -v b="$cpu1" -v t="$ticks" -v s="$seconds" 'BEGIN { printf "  processor: %.3f%% (%.2f s over %d s)\n", (b - a) / t / s * 100, (b - a) / t, s }'
echo "  wake-ups: $((wake1 - wake0)) in ${seconds}s"
echo "  threads: $threads"
kill "$pid"

#!/bin/bash
# scripts/make-readme-gifs.sh: turns the films of the real app into the README's animated pictures.
#
#   scripts/make-readme-gifs.sh [WINDOWS_FRAMES] [LINUX_FRAMES]
#
# The Mac's films come from scripts/capture-site.sh (COL_PARTS=gifs): .build/site-shots/readme-*.mov. Windows and
# Linux film themselves on CI (windows/tools/screenshots.ps1, linux/tools/screenshots.sh with COL_FILM=1): pass the
# folders of frames from their "screenshots" artifacts. Nothing is drawn here: each picture is the app itself.
set -euo pipefail
cd "$(dirname "$0")/.."
SHOTS=.build/site-shots
OUT=docs/images
command -v ffmpeg >/dev/null || { echo "ffmpeg is missing: brew install ffmpeg" >&2; exit 1; }
mkdir -p "$OUT"

# gif <input options...> -- <output> <fps> <width>: a palette made for the film itself, refreshed where frames change,
# and the last frame held a moment before the picture starts again.
gif() {
  local args=()
  while [ "$1" != -- ]; do args+=("$1"); shift; done
  shift
  local output=$1 fps=$2 width=$3
  ffmpeg -loglevel error -y "${args[@]}" -vf \
    "tpad=stop_mode=clone:stop_duration=0.8,fps=$fps,scale=$width:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=200:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    -loop 0 "$output"
  printf '  %-34s %6s KB\n' "$output" "$(( $(stat -f %z "$output") / 1024 ))"
}

# The films start 1.2 seconds before Col opens (scripts/capture-site.sh, take): the pictures start a second in, so the
# bare desktop shows only a moment before the island comes.
LEAD_IN=1.0

echo "README pictures:"
for name in notch pill drawers; do
  film="$SHOTS/readme-$name.mov"
  [ -f "$film" ] && gif -ss "$LEAD_IN" -i "$film" -- "$OUT/readme-$name.gif" 20 760
done
if [ -n "${1:-}" ] && [ -d "$1" ]; then
  gif -framerate 25 -i "$1/frame-%04d.png" -- "$OUT/readme-windows.gif" 20 760
fi
if [ -n "${2:-}" ] && [ -d "$2" ]; then
  gif -framerate 20 -i "$2/frame-%04d.png" -- "$OUT/readme-linux.gif" 20 760
fi

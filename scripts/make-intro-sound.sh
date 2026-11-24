#!/bin/bash
# scripts/make-intro-sound.sh: writes Col's opening chime with scripts/make-intro-sound.swift, then what each system
# bundles: AAC for the Mac, 16-bit WAV at 32 kHz for Windows (SoundPlayer plays WAV only) and Linux (any player).
#
#   scripts/make-intro-sound.sh
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swift scripts/make-intro-sound.swift "$TMP/intro.wav"
afconvert -f m4af -d aac -b 96000 "$TMP/intro.wav" Packages/ColKit/Sources/ColShell/Resources/Intro.m4a
afconvert -f WAVE -d LEI16@32000 "$TMP/intro.wav" windows/src/Col/Assets/intro.wav
cp windows/src/Col/Assets/intro.wav linux/data/sounds/intro.wav
ls -l Packages/ColKit/Sources/ColShell/Resources/Intro.m4a windows/src/Col/Assets/intro.wav linux/data/sounds/intro.wav

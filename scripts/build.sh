#!/bin/bash
# scripts/build.sh: generates the Xcode project with XcodeGen and builds Islet.app into .build/xcode, or into
# ISLET_BUILD_DIR when it is set (a folder outside the clone, for a clone kept in a synced folder such as iCloud
# Drive, whose file attributes can make codesign refuse the app).
#
#   scripts/build.sh [Debug|Release]
#
# Signing: ad hoc by default, with the hardened runtime off. Set ISLET_TEAM_ID to your Apple team ID to sign with
# your Apple Development certificate instead.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${1:-Debug}"
case "$CONFIGURATION" in
  Debug|Release) ;;
  *) echo "usage: scripts/build.sh [Debug|Release]" >&2; exit 64 ;;
esac
command -v xcodegen >/dev/null || { echo "XcodeGen is missing: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
SIGNING=(ENABLE_HARDENED_RUNTIME=NO)
if [ -n "${ISLET_TEAM_ID:-}" ]; then
  SIGNING=(-allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$ISLET_TEAM_ID" CODE_SIGN_IDENTITY="Apple Development")
fi
BUILD_DIR="${ISLET_BUILD_DIR:-.build/xcode}"
mkdir -p "$BUILD_DIR"
LOG="$BUILD_DIR/build.log"
xcodebuild -project Islet.xcodeproj -scheme Islet -configuration "$CONFIGURATION" -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR" -clonedSourcePackagesDirPath .build/spm ${SIGNING[@]+"${SIGNING[@]}"} build > "$LOG" 2>&1 \
  || { grep -E "error:" "$LOG" | head -20 >&2; tail -n 20 "$LOG" >&2; exit 1; }
APP="$BUILD_DIR/Build/Products/$CONFIGURATION/Islet.app"
codesign --verify --strict "$APP"
echo "$APP"

#!/bin/bash
# scripts/finish-release.sh <version>: turns the notarized dist/Col-<version>.dmg into everything a release
# publishes, and publishes nothing: the stapled image and its stable copies dist/Col.dmg and dist/Islet.dmg (for the
# links made before 2.0), its SHA-256, the release notes (from CHANGELOG.md), the Homebrew cask and the new appcast item,
# EdDSA-signed with the key in the login keychain (account "islet"; macOS asks once to let generate_appcast use it).
# scripts/release.sh runs it; after NOTARIZE_LATER, run it yourself.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/finish-release.sh <version>}"
REPO_URL=https://github.com/ruben4reall/col
SITE_URL=https://getcol.vercel.app
ACCOUNT=islet  # the Sparkle key keeps the name it was made under
APPCAST=site/appcast.xml
PREFIX="$REPO_URL/releases/download/v$VERSION/"
DMG="dist/Col-$VERSION.dmg"
fail() { echo "finish-release: $*" >&2; exit 1; }
[ -f "$DMG" ] || fail "$DMG is missing: run scripts/release.sh first"

# 1. Apple's ticket goes into the image first: stapling changes its bytes, and everything below signs or hashes them.
xcrun stapler staple "$DMG" >/dev/null || fail "Apple has not accepted $DMG yet"
xcrun stapler validate "$DMG" >/dev/null || fail "$DMG carries no valid ticket"
hdiutil verify "$DMG" >/dev/null 2>&1 || fail "$DMG does not verify"
cp "$DMG" dist/Col.dmg
# Islet's README, website and posts link to .../releases/latest/download/Islet.dmg, which GitHub follows to the renamed
# repository's latest release: each release carries the same image under that name too, so those links download Col.
cp "$DMG" dist/Islet.dmg
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "$SHA  Col-$VERSION.dmg" > "dist/Col-$VERSION.dmg.sha256"

# 2. Release notes, for GitHub and for Sparkle's update window.
NOTES=$(scripts/changelog-section.sh "$VERSION")
UPDATES=.build/release-updates
rm -rf "$UPDATES" && mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
printf '%s\n' "$NOTES" > "$UPDATES/Col-$VERSION.md"
{
  printf '%s\n\n' "$NOTES"
  printf 'SHA-256 of Col-%s.dmg: `%s`\n\n' "$VERSION" "$SHA"
  printf 'Col is not affiliated with Apple.\n'
} > dist/release-notes.md

# 3. The appcast: the new item on top, older items kept.
GENERATE_APPCAST=$(find .build/spm/artifacts -type f -name generate_appcast -perm -u+x 2>/dev/null | head -1)
[ -n "$GENERATE_APPCAST" ] || fail "Sparkle's tools are missing from .build/spm: build with scripts/release.sh first"
# The key: the file exported next to the repository (gitignored) when present, otherwise the login keychain.
if [ -f .env.sparkle-private-key ]; then KEY=(--ed-key-file .env.sparkle-private-key); else KEY=(--account "$ACCOUNT"); fi
"$GENERATE_APPCAST" "${KEY[@]}" --download-url-prefix "$PREFIX" --link "$SITE_URL" \
  --full-release-notes-url "$REPO_URL/releases" --embed-release-notes --maximum-deltas 0 -o "$APPCAST" "$UPDATES"
grep -q "sparkle:edSignature" "$APPCAST" || fail "$APPCAST has no EdDSA signature"

# 4. The cask for the tap (ruben4reall/homebrew-tap). It took over from the islet cask: the tap's cask_renames.json
#    maps "islet" to "col" and has no Casks/islet.rb any more, so `brew upgrade --cask --greedy col` moves Islet's
#    Homebrew users to Col.app. The tap's other renames stay as they are.
mkdir -p dist/homebrew/Casks
scripts/render-cask.sh "$VERSION" "$SHA" > dist/homebrew/Casks/col.rb

echo "Ready: $DMG, dist/Col.dmg, dist/Islet.dmg (for links made before 2.0), dist/release-notes.md, $APPCAST, dist/homebrew/Casks/col.rb"
echo "Publication, on Ruben's go-ahead: the GitHub release v$VERSION with the three disk images (Col-$VERSION.dmg, Col.dmg,"
echo "Islet.dmg), the site right after it, then the tap."
echo "The tap needs \"islet\": \"col\" in its cask_renames.json and no Casks/islet.rb."

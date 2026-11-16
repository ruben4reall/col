#!/bin/sh
# Builds Col's tarball: the programs, their data and translations, and a script that installs them for one user
# (~/.local) or for everyone (/usr/local). The system provides GTK 4, libadwaita and the other libraries;
# gtk4-layer-shell is built into the program.
#
#   packaging/linux/build-tarball.sh BUILD_DIR OUT_DIR
#
# Writes OUT_DIR/Col-<version>-linux-<arch>.tar.gz.
set -eu

build=$(realpath "$1")
out=$2
mkdir -p "$out"
out=$(realpath "$out")
here=$(cd "$(dirname "$0")" && pwd)
version=$(meson introspect "$build" --projectinfo | python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])')
arch=$(uname -m)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
name="Col-$version"
DESTDIR="$work/stage" meson install -C "$build" --no-rebuild --skip-subprojects --quiet
prefix=$(meson introspect "$build" --buildoptions | python3 -c 'import json, sys; print(next(o["value"] for o in json.load(sys.stdin) if o["name"] == "prefix"))')
mv "$work/stage$prefix" "$work/$name"
strip --strip-unneeded "$work/$name/bin/col-island" "$work/$name/bin/colctl"
cp "$here/install.sh" "$work/$name/install.sh"
chmod 0755 "$work/$name/install.sh"
cp "$here/../../LICENSE" "$work/$name/LICENSE"
cp "$here/../../linux/README.md" "$work/$name/README.md"
cp "$here/../../linux/THIRD-PARTY-NOTICES.md" "$work/$name/THIRD-PARTY-NOTICES.md"

archive="$out/$name-linux-$arch.tar.gz"
tar -C "$work" --owner=0 --group=0 --numeric-owner -czf "$archive" "$name"
echo "$archive"

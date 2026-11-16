#!/bin/sh
# Builds Col's Debian package from a meson build of linux/, for Ubuntu 24.04 and later and Debian 13, on the
# architecture it runs on (amd64 or arm64). The dependencies are the libraries the binaries link to, as dpkg-shlibdeps
# finds them; gtk4-layer-shell, which Ubuntu 24.04 does not have, is built into the program.
#
#   packaging/linux/build-deb.sh BUILD_DIR OUT_DIR
#
# Writes OUT_DIR/col_<version>_<arch>.deb.
set -eu

build=$(realpath "$1")
out=$2
mkdir -p "$out"
out=$(realpath "$out")
version=$(meson introspect "$build" --projectinfo | python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])')
arch=$(dpkg --print-architecture)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root="$work/root"
DESTDIR="$root" meson install -C "$build" --no-rebuild --skip-subprojects --quiet
strip --strip-unneeded "$root/usr/bin/col-island" "$root/usr/bin/colctl"

# dpkg-shlibdeps reads a debian/control: a minimal one, in a folder of its own.
mkdir -p "$work/shlibs/debian"
printf 'Source: col\n\nPackage: col\nArchitecture: any\n' >"$work/shlibs/debian/control"
depends=$(cd "$work/shlibs" && dpkg-shlibdeps -O "$root/usr/bin/col-island" "$root/usr/bin/colctl" | sed -n 's/^shlibs:Depends=//p')
size=$(du -sk "$root/usr" | cut -f1)

mkdir -p "$root/DEBIAN"
cat >"$root/DEBIAN/control" <<EOF
Package: col
Version: $version
Architecture: $arch
Maintainer: Ruben Catalao <ruben.ctlo@protonmail.com>
Installed-Size: $size
Depends: $depends
Recommends: adwaita-icon-theme, xdg-desktop-portal
Section: utils
Priority: optional
Homepage: https://getcol.vercel.app
Description: the island at the top of your screen
 Col puts a small black island at the top of the screen. While you work it
 shows the song playing with its synced lyrics, a coding agent waiting for
 you (Claude Code and Codex, with Allow and Deny), the volume, the battery,
 a timer and your own live activities from the colctl command.
 .
 A preview of the first Linux edition. Best on desktops with layer-shell:
 KDE Plasma, COSMIC, Hyprland, Sway, niri, Wayfire. On GNOME the island runs
 under XWayland, below the top bar.
EOF

# After installing or removing: the menus and the col:// links learn about Col.
cat >"$root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
fi
exit 0
EOF
cat >"$root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] || [ "$1" = purge ]; then
    command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
fi
exit 0
EOF
chmod 0755 "$root/DEBIAN/postinst" "$root/DEBIAN/postrm"

mkdir -p "$root/usr/share/doc/col"
{
    cat "$(dirname "$0")/../../LICENSE"
    echo
    cat "$(dirname "$0")/../../linux/THIRD-PARTY-NOTICES.md"
} >"$root/usr/share/doc/col/copyright"
chmod 0644 "$root/usr/share/doc/col/copyright"
find "$root" -type d -exec chmod 0755 {} +

package="$out/col_${version}_${arch}.deb"
dpkg-deb --root-owner-group -Zxz --build "$root" "$package" >/dev/null
echo "$package"

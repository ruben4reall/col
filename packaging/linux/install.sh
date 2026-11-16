#!/bin/sh
# Installs Col from this folder: for you alone in ~/.local (the default), or for everyone with --system (/usr/local,
# run with sudo). --uninstall takes it away again. Col needs GTK 4.14 or later, libadwaita 1.5 or later, libsoup 3,
# json-glib and libpulse, which most desktops already have.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
prefix="$HOME/.local"
action=install
for arg in "$@"; do
    case "$arg" in
        --system) prefix=/usr/local ;;
        --uninstall) action=uninstall ;;
        --prefix=*) prefix=${arg#--prefix=} ;;
        *) echo "usage: install.sh [--system | --prefix=DIR] [--uninstall]" >&2; exit 2 ;;
    esac
done

files="bin/col-island bin/colctl share/applications/ch.rubencatalao.Col.desktop share/metainfo/ch.rubencatalao.Col.metainfo.xml share/locale/fr/LC_MESSAGES/col.mo"
for size in 16 24 32 48 64 128 256 512; do
    files="$files share/icons/hicolor/${size}x${size}/apps/ch.rubencatalao.Col.png"
done

refresh() {
    command -v update-desktop-database >/dev/null && update-desktop-database -q "$prefix/share/applications" 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$prefix/share/icons/hicolor" 2>/dev/null || true
}

if [ "$action" = uninstall ]; then
    for file in $files; do
        rm -f "$prefix/$file"
    done
    refresh
    echo "Col removed from $prefix. Your settings stay in ~/.config/col; disconnect your agents first with: colctl hooks uninstall --agent all"
    exit 0
fi

for file in $files; do
    mkdir -p "$(dirname "$prefix/$file")"
    cp "$here/$file" "$prefix/$file"
done
# The menu entry names the program by its full path when that folder may not be on the PATH.
case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) sed -i "s|^Exec=col-island|Exec=$prefix/bin/col-island|" "$prefix/share/applications/ch.rubencatalao.Col.desktop" ;;
esac
refresh

missing=$(ldd "$prefix/bin/col-island" 2>/dev/null | awk '/not found/ {print $1}' | tr '\n' ' ')
if [ -n "$missing" ]; then
    echo "Col is installed in $prefix, but these libraries are missing: $missing"
    echo "On Debian or Ubuntu: sudo apt install libgtk-4-1 libadwaita-1-0 libsoup-3.0-0 libjson-glib-1.0-0 libpulse0 libpulse-mainloop-glib0"
    echo "On Fedora: sudo dnf install gtk4 libadwaita libsoup3 json-glib pulseaudio-libs-glib2"
    echo "On Arch: sudo pacman -S gtk4 libadwaita libsoup3 json-glib libpulse"
    exit 1
fi
echo "Col is installed in $prefix. Open it from your applications, or run: $prefix/bin/col-island"

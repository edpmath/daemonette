#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

echo "==> Uninstalling Daemonette from ${PREFIX}..."
rm -f "${PREFIX}/bin/daemonette"
rm -f "${PREFIX}/share/applications/io.github.edpmath.Daemonette.desktop"
rm -f "${PREFIX}/share/metainfo/io.github.edpmath.Daemonette.metainfo.xml"

for size in 16x16 24x24 32x32 64x64 128x128 256x256 512x512; do
    rm -f "${PREFIX}/share/icons/hicolor/${size}/apps/daemonette.png"
done

if which gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f "${PREFIX}/share/icons/hicolor" 2>/dev/null || true
fi
if which update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "${PREFIX}/share/applications" 2>/dev/null || true
fi

echo "==> Daemonette uninstalled successfully."

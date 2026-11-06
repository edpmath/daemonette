#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing Daemonette to ${PREFIX}..."
install -d "${PREFIX}/bin"
install -m 0755 "${DIR}/bin/daemonette" "${PREFIX}/bin/daemonette"

install -d "${PREFIX}/share/applications"
install -m 0644 "${DIR}/share/applications/io.github.edpmath.Daemonette.desktop" "${PREFIX}/share/applications/"

install -d "${PREFIX}/share/metainfo"
install -m 0644 "${DIR}/share/metainfo/io.github.edpmath.Daemonette.metainfo.xml" "${PREFIX}/share/metainfo/"

for size in 16x16 24x24 32x32 64x64 128x128 256x256 512x512; do
    if [ -f "${DIR}/share/icons/hicolor/${size}/apps/daemonette.png" ]; then
        install -d "${PREFIX}/share/icons/hicolor/${size}/apps"
        install -m 0644 "${DIR}/share/icons/hicolor/${size}/apps/daemonette.png" "${PREFIX}/share/icons/hicolor/${size}/apps/"
    fi
done

if which gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f "${PREFIX}/share/icons/hicolor" 2>/dev/null || true
fi
if which update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "${PREFIX}/share/applications" 2>/dev/null || true
fi

echo "==> Daemonette installed successfully! Run 'daemonette' to launch."

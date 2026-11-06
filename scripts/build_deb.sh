#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
STAGING_DIR="${BUILD_DIR}/deb_staging"
PACKAGE_NAME="daemonette"
VERSION="$("${ROOT_DIR}/scripts/version.sh")"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"
OUTPUT_DEB="${BUILD_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

echo "==> Ensuring build directory is configured..."
if [ ! -f "${BUILD_DIR}/build.ninja" ]; then
    meson setup "${BUILD_DIR}" --buildtype=release --prefix=/usr
fi

echo "==> Building ${PACKAGE_NAME} binary with Ninja..."
ninja -C "${BUILD_DIR}"

echo "==> Preparing staging area at ${STAGING_DIR}..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

echo "==> Installing files into staging directory..."
DESTDIR="${STAGING_DIR}" ninja -C "${BUILD_DIR}" install

echo "==> Installing Debian package control scripts..."
mkdir -p "${STAGING_DIR}/DEBIAN"
cp "${ROOT_DIR}/packaging/debian/control" "${STAGING_DIR}/DEBIAN/control"

# Inject the project version (read from meson.build) into the staged control
sed -i "s/^Version:.*/Version: ${VERSION}/" "${STAGING_DIR}/DEBIAN/control"
cp "${ROOT_DIR}/packaging/debian/postinst" "${STAGING_DIR}/DEBIAN/postinst"
cp "${ROOT_DIR}/packaging/debian/postrm" "${STAGING_DIR}/DEBIAN/postrm"

chmod 0755 "${STAGING_DIR}/DEBIAN/postinst"
chmod 0755 "${STAGING_DIR}/DEBIAN/postrm"
chmod 0644 "${STAGING_DIR}/DEBIAN/control"

# Ensure binary is executable
if [ -f "${STAGING_DIR}/usr/bin/daemonette" ]; then
    chmod 0755 "${STAGING_DIR}/usr/bin/daemonette"
elif [ -f "${STAGING_DIR}/usr/local/bin/daemonette" ]; then
    # In case prefix was /usr/local, move to /usr
    mkdir -p "${STAGING_DIR}/usr"
    mv "${STAGING_DIR}/usr/local/bin" "${STAGING_DIR}/usr/" 2>/dev/null || true
    mv "${STAGING_DIR}/usr/local/share" "${STAGING_DIR}/usr/" 2>/dev/null || true
    rm -rf "${STAGING_DIR}/usr/local"
    chmod 0755 "${STAGING_DIR}/usr/bin/daemonette"
fi

echo "==> Building .deb package with dpkg-deb..."
dpkg-deb --build --root-owner-group "${STAGING_DIR}" "${OUTPUT_DEB}"

echo ""
echo "=========================================================="
echo " [OK] Package generated successfully:"
echo "      ${OUTPUT_DEB}"
echo "=========================================================="
echo ""
dpkg-deb --info "${OUTPUT_DEB}"
echo ""
dpkg-deb --contents "${OUTPUT_DEB}"

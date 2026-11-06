#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Dedicated build directory for packaging: it is always configured with
# prefix=/usr, so the .deb layout is correct regardless of the prefix used
# by the user's regular development build/ directory.
PACKAGE_BUILD_DIR="${ROOT_DIR}/build-deb"
STAGING_DIR="${PACKAGE_BUILD_DIR}/deb_staging"
PACKAGE_NAME="daemonette"
VERSION="$("${ROOT_DIR}/scripts/version.sh")"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"
OUTPUT_DIR="${ROOT_DIR}/build"
OUTPUT_DEB="${OUTPUT_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

echo "==> Packaging version: ${VERSION}"
echo "==> Ensuring packaging build directory is configured (prefix=/usr)..."
if [ ! -f "${PACKAGE_BUILD_DIR}/build.ninja" ]; then
    meson setup "${PACKAGE_BUILD_DIR}" --buildtype=release --prefix=/usr
fi

echo "==> Building ${PACKAGE_NAME} binary with Ninja..."
ninja -C "${PACKAGE_BUILD_DIR}"

echo "==> Preparing staging area at ${STAGING_DIR}..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

echo "==> Installing files into staging directory..."
mkdir -p "${OUTPUT_DIR}"
DESTDIR="${STAGING_DIR}" ninja -C "${PACKAGE_BUILD_DIR}" install

echo "==> Installing Debian package control scripts..."
mkdir -p "${STAGING_DIR}/DEBIAN"
# Install control scripts; strip human-oriented comment lines because
# dpkg-deb does not accept comments in the binary package control file
sed '/^[[:space:]]*#/d' "${ROOT_DIR}/packaging/debian/control" > "${STAGING_DIR}/DEBIAN/control"

# Inject the project version (read from meson.build) into the staged control
sed -i "s/^Version:.*/Version: ${VERSION}/" "${STAGING_DIR}/DEBIAN/control"
cp "${ROOT_DIR}/packaging/debian/postinst" "${STAGING_DIR}/DEBIAN/postinst"
cp "${ROOT_DIR}/packaging/debian/postrm" "${STAGING_DIR}/DEBIAN/postrm"

chmod 0755 "${STAGING_DIR}/DEBIAN/postinst"
chmod 0755 "${STAGING_DIR}/DEBIAN/postrm"
chmod 0644 "${STAGING_DIR}/DEBIAN/control"

# Binary must be executable inside the package
chmod 0755 "${STAGING_DIR}/usr/bin/daemonette"

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

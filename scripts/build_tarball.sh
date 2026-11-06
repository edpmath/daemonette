#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
VERSION="$("${ROOT_DIR}/scripts/version.sh")"
ARCH="$(uname -m)"
DIST_NAME="daemonette-${VERSION}-linux-${ARCH}"
STAGING_DIR="${BUILD_DIR}/${DIST_NAME}"
OUTPUT_TAR="${BUILD_DIR}/${DIST_NAME}.tar.gz"

echo "==> Ensuring build directory is configured..."
if [ ! -f "${BUILD_DIR}/build.ninja" ]; then
    meson setup "${BUILD_DIR}" --buildtype=release --prefix=/usr
fi

echo "==> Compiling with Ninja..."
ninja -C "${BUILD_DIR}"

echo "==> Staging files for tarball in ${STAGING_DIR}..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}/bin" "${STAGING_DIR}/share"

cp "${BUILD_DIR}/daemonette" "${STAGING_DIR}/bin/"
chmod 0755 "${STAGING_DIR}/bin/daemonette"

mkdir -p "${STAGING_DIR}/share/applications"
cp "${ROOT_DIR}/data/io.github.edpmath.Daemonette.desktop" "${STAGING_DIR}/share/applications/"

mkdir -p "${STAGING_DIR}/share/metainfo"
cp "${ROOT_DIR}/data/io.github.edpmath.Daemonette.metainfo.xml" "${STAGING_DIR}/share/metainfo/"

mkdir -p "${STAGING_DIR}/share/icons/hicolor"
cp -r "${ROOT_DIR}/data/icons/hicolor/"* "${STAGING_DIR}/share/icons/hicolor/"

cp "${ROOT_DIR}/packaging/tarball/install.sh" "${STAGING_DIR}/"
cp "${ROOT_DIR}/packaging/tarball/uninstall.sh" "${STAGING_DIR}/"
chmod 0755 "${STAGING_DIR}/install.sh" "${STAGING_DIR}/uninstall.sh"

cp "${ROOT_DIR}/LICENSE" "${STAGING_DIR}/"
cp "${ROOT_DIR}/README.md" "${STAGING_DIR}/"

echo "==> Creating tarball ${OUTPUT_TAR}..."
tar -czf "${OUTPUT_TAR}" -C "${BUILD_DIR}" "${DIST_NAME}"
rm -rf "${STAGING_DIR}"

echo ""
echo "=========================================================="
echo " [OK] Universal Tarball generated successfully:"
echo "      ${OUTPUT_TAR}"
echo "=========================================================="
ls -lh "${OUTPUT_TAR}"
echo ""
tar -tzf "${OUTPUT_TAR}"

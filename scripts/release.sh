#!/usr/bin/env bash
# ============================================================================
# scripts/release.sh
# Bump the application version across all "version declaration" files in one
# shot. To be used right before publishing a tag (e.g. git tag v1.2.0).
#
# Usage:
#   ./scripts/release.sh 1.2.0        (or: make release VERSION=1.2.0)
#
# What it does:
#   1. Updates the version in meson.build (single source of truth)
#   2. Adds a new <release> entry to the AppStream metainfo.xml
#   3. Prepends a new entry to the RPM %changelog
#      (the .deb control file and the tarball/deb/RPM scripts read the
#      version dynamically from meson.build, so nothing else to touch)
#
# Idempotent: re-running with the same version does nothing.
# ============================================================================
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") <version>   (e.g. 1.2.0)" >&2
    exit 1
fi
NEW_VERSION="$1"

if [[ ! "${NEW_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: '${NEW_VERSION}' is not a valid X.Y.Z version" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MESON="${ROOT_DIR}/meson.build"
METAINFO="${ROOT_DIR}/data/io.github.edpmath.Daemonette.metainfo.xml"
SPEC="${ROOT_DIR}/packaging/rpm/daemonette.spec"

CURRENT="$(sed -n "s/^[[:space:]]*version[[:space:]]*:[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" "${MESON}" | head -n1)"
if [ -z "${CURRENT}" ]; then
    echo "ERROR: could not read current version from meson.build" >&2
    exit 1
fi

if [ "${NEW_VERSION}" = "${CURRENT}" ]; then
    echo "==> Already at version ${NEW_VERSION}. Nothing to do."
    exit 0
fi

echo "==> Bumping Daemonette: ${CURRENT} -> ${NEW_VERSION}"

DATE_ISO="$(date +%F)"
DATE_RPM="$(LC_ALL=C date '+%a %b %d %Y')"

GIT_NAME="$(git -C "${ROOT_DIR}" config user.name 2>/dev/null || true)"
GIT_EMAIL="$(git -C "${ROOT_DIR}" config user.email 2>/dev/null || true)"
[ -n "${GIT_NAME}" ]  || GIT_NAME="Elias Peraza"
[ -n "${GIT_EMAIL}" ] || GIT_EMAIL="edpmath@users.noreply.github.com"

# ----------------------------------------------------------------------------
# 1. meson.build — the single source of truth
# ----------------------------------------------------------------------------
if ! grep -q "version[[:space:]]*:[[:space:]]*['\"]${NEW_VERSION}['\"]" "${MESON}"; then
    sed -i -E "s|^([[:space:]]*version[[:space:]]*:[[:space:]]*)(['\"]).*\\2|\1\\2${NEW_VERSION}\\2|" "${MESON}"
    echo "   [OK] meson.build -> ${NEW_VERSION}"
fi

# ----------------------------------------------------------------------------
# 2. AppStream metainfo — newest release must be the first entry
# ----------------------------------------------------------------------------
if ! grep -q "release version=\"${NEW_VERSION}\"" "${METAINFO}"; then
    sed -i "s|<releases>|<releases>\\
    <release version=\"${NEW_VERSION}\" date=\"${DATE_ISO}\">\\
      <description>\\
        <p>Release of Daemonette ${NEW_VERSION}.</p>\\
        <p xml:lang=\"es\">Lanzamiento de Daemonette ${NEW_VERSION}.</p>\\
      </description>\\
    </release>|" "${METAINFO}"
    echo "   [OK] metainfo: added <release ${NEW_VERSION} ${DATE_ISO}>"
fi

# ----------------------------------------------------------------------------
# 3. RPM %changelog — newest entry goes right after %changelog
# ----------------------------------------------------------------------------
if ! grep -qE -- "^\\* .* - ${NEW_VERSION//./\\.}-[0-9]+$" "${SPEC}"; then
    ENTRY="* ${DATE_RPM} ${GIT_NAME} <${GIT_EMAIL}> - ${NEW_VERSION}-1
- Release ${NEW_VERSION}"
    ENTRY="${ENTRY}" awk '
        /^%changelog$/ && !done { print; print ENVIRON["ENTRY"]; done=1; next }
        { print }
    ' "${SPEC}" > "${SPEC}.tmp" && mv "${SPEC}.tmp" "${SPEC}"
    echo "   [OK] spec: added %changelog entry for ${NEW_VERSION}-1"
fi

# ----------------------------------------------------------------------------
# Sanity check: the messaging used by every packaging script must match now
# ----------------------------------------------------------------------------
Bumped="$("${ROOT_DIR}/scripts/version.sh")"
echo ""
echo "==> Done. scripts/version.sh reports: ${Bumped}"
echo ""
echo "Next steps:"
echo "    git commit -am \"Release ${NEW_VERSION}\""
echo "    git tag v${NEW_VERSION}"
echo "    git push origin main --tags"

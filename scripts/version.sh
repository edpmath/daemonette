#!/usr/bin/env bash
# ============================================================================
# scripts/version.sh
# Single source of truth for the application version: meson.build.
#
# Usage:
#   VERSION="$(./scripts/version.sh)"
#   or just: ./scripts/version.sh   (prints the version to stdout)
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n "s/^[[:space:]]*version[[:space:]]*:[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" "${ROOT_DIR}/meson.build" | head -n1)"

if [ -z "${VERSION}" ]; then
    echo "ERROR: could not read project version from meson.build" >&2
    exit 1
fi

echo "${VERSION}"

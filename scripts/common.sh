#!/usr/bin/env bash
# Shared helpers for the setup / run scripts.
#
# Package definitions live in packages/<name>/ (committed); the downstream
# sources they describe are cloned into checkouts/<name>/ (generated). All
# reading of the definitions goes through scripts/pkglib.py so bash and python
# agree on one parser.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # read by the scripts that source this file
PKGDEFS_DIR="${ROOT_DIR}/packages"
PKGLIB="${ROOT_DIR}/scripts/pkglib.py"

# Overridable so the matrix job can point the report at a directory of
# downloaded per-package artifacts instead of a local run's output.
CHECKOUTS_DIR="${CHECKOUTS_DIR:-${ROOT_DIR}/checkouts}"
LOGS_DIR="${LOGS_DIR:-${ROOT_DIR}/logs}"
RESULTS_DIR="${RESULTS_DIR:-${ROOT_DIR}/results}"

mkdir -p "${CHECKOUTS_DIR}" "${LOGS_DIR}" "${RESULTS_DIR}"

# Pin build-time (PEP 518) dependencies for every `uv pip install` in the run,
# including the ones inside a package's test.sh. A build-backend release can
# stop an older downstream pin from building at all, which looks like a testbed
# failure but says nothing about Tornado. See build-constraints.txt.
export UV_BUILD_CONSTRAINT="${UV_BUILD_CONSTRAINT:-${ROOT_DIR}/build-constraints.txt}"

# All package names, in rank (popularity) order.
pkg_names() { python3 "${PKGLIB}" names; }

pkg_count() { python3 "${PKGLIB}" count; }

# pkg_resolve <name-or-rank> -> canonical name
pkg_resolve() { python3 "${PKGLIB}" resolve "$1"; }

# pkg_load <name> -- emit shell assignments for one package's definition.
# Use as: eval "$(pkg_load flower)"  =>  PKG_NAME, PKG_REPO, PKG_REF,
# PKG_SUBDIR, PKG_INSTALL_METHOD, PKG_PYPI_EXTRA_DEPS, PKG_VERSION,
# PKG_DIST_NAME, PKG_DIR, PKG_REQUIREMENTS, PKG_TEST_SH, PKG_SETUP_SH.
pkg_load() { python3 "${PKGLIB}" env "$1"; }

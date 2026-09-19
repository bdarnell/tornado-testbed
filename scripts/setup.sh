#!/usr/bin/env bash
# Clone (or update) downstream sources into checkouts/<name>/ at the ref implied
# by each package's pin.
#
#   scripts/setup.sh                  every package
#   scripts/setup.sh flower bokeh     just these (by name or rank)
#
# Safe to re-run: an existing checkout is fetched and checked out at the ref.
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [[ $# -gt 0 ]]; then
    names=()
    for sel in "$@"; do
        names+=("$(pkg_resolve "${sel}")")
    done
else
    mapfile -t names < <(pkg_names)
fi

echo "Setting up ${#names[@]} package(s) into ${CHECKOUTS_DIR}"

for name in "${names[@]}"; do
    eval "$(pkg_load "${name}")"
    dest="${CHECKOUTS_DIR}/${PKG_NAME}"

    echo ""
    echo "=== ${PKG_NAME} @ ${PKG_REF} (${PKG_DIST_NAME}==${PKG_VERSION}) ==="

    if [[ -d "${dest}/.git" ]]; then
        echo "Already cloned; fetching ${PKG_REF}..."
        # Fetch tags too — setuptools_scm / versioneer need them.
        git -C "${dest}" fetch --tags origin "${PKG_REF}" || \
            git -C "${dest}" fetch origin "${PKG_REF}"
        git -C "${dest}" checkout -f "${PKG_REF}"
    else
        echo "Cloning ${PKG_REPO}..."
        # Shallow clone with tags. --no-single-branch + --depth 1 keeps size
        # down but still gives setuptools_scm the tag it needs.
        git clone --depth 1 --branch "${PKG_REF}" --no-single-branch \
            "${PKG_REPO}" "${dest}" 2>/dev/null || {
            # Fallback: full clone + checkout.
            git clone "${PKG_REPO}" "${dest}"
            git -C "${dest}" checkout "${PKG_REF}"
        }
        # Ensure the ref tag exists locally so `git describe` works.
        git -C "${dest}" fetch --tags --depth 1 origin "${PKG_REF}" 2>/dev/null || true
    fi

    echo "HEAD: $(git -C "${dest}" rev-parse --short HEAD)"
done

echo ""
echo "Setup complete. Checkouts under ${CHECKOUTS_DIR}"

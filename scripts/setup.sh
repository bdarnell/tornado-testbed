#!/usr/bin/env bash
# Clone (or update) each dependent package at its pinned ref.
# Safe to re-run: already-cloned packages are fast-forwarded to the pinned ref.
set -euo pipefail
source "$(dirname "$0")/common.sh"

N="$(pkg_count)"
echo "Setting up ${N} packages into ${PACKAGES_DIR}"

for ((i = 0; i < N; i++)); do
    name="$(pkg_field "$i" name)"
    repo="$(pkg_field "$i" repo)"
    ref="$(pkg_field "$i" ref)"
    dest="${PACKAGES_DIR}/${name}"

    echo ""
    echo "=== [${i}] ${name} @ ${ref} ==="

    if [[ -d "${dest}/.git" ]]; then
        echo "Already cloned; fetching ${ref}..."
        # Fetch tags too — setuptools_scm / versioneer need them.
        git -C "${dest}" fetch --tags origin "${ref}" || \
            git -C "${dest}" fetch origin "${ref}"
        git -C "${dest}" checkout -f "${ref}"
    else
        echo "Cloning ${repo}..."
        # Shallow clone with tags. --no-single-branch + --depth 1 keeps size
        # down but still gives setuptools_scm the tag it needs.
        git clone --depth 1 --branch "${ref}" --no-single-branch "${repo}" "${dest}" 2>/dev/null || {
            # Fallback: full clone + checkout.
            git clone "${repo}" "${dest}"
            git -C "${dest}" checkout "${ref}"
        }
        # Ensure the ref tag exists locally so `git describe` works.
        git -C "${dest}" fetch --tags --depth 1 origin "${ref}" 2>/dev/null || true
    fi

    head="$(git -C "${dest}" rev-parse --short HEAD)"
    echo "HEAD: ${head}"
done

echo ""
echo "Setup complete. Packages under ${PACKAGES_DIR}"

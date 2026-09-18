#!/usr/bin/env bash
# Print the package names touched between a base ref and HEAD, space-separated.
#
# Used by the `pins` workflow so a dependabot version bump is validated by
# running the package it actually changed, rather than all ten.
#
#   scripts/changed_packages.sh origin/main
#
# Prints nothing (and exits 0) when no package directory changed. A name is only
# printed if the directory still holds a package.env, so deleting a package does
# not ask the workflow to run something that no longer exists.
set -euo pipefail
source "$(dirname "$0")/common.sh"

usage() { echo "usage: $0 <base-ref>" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
base="$1"

# Three dots: changes on this branch since it diverged, not changes the base
# has picked up meanwhile.
mapfile -t changed < <(
    git -C "${ROOT_DIR}" diff --name-only "${base}...HEAD" -- packages/ \
        | awk -F/ 'NF >= 2 {print $2}' \
        | sort -u
)

names=()
for name in "${changed[@]}"; do
    [[ -f "${PKGDEFS_DIR}/${name}/package.env" ]] && names+=("${name}")
done

[[ "${#names[@]}" -gt 0 ]] && echo "${names[*]}"
exit 0

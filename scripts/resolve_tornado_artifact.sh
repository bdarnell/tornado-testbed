#!/usr/bin/env bash
# Turn a directory of downloaded tornado build artifacts into a TORNADO_SPEC and
# the version we expect to see installed.
#
# Used when the testbed runs inside tornado's own build: a called reusable
# workflow shares the caller's workflow run, so actions/download-artifact can
# fetch the sdist/wheel that run just built. Testing that exact artifact is the
# point -- a git ref would be re-resolved and re-built.
#
# Prints two key=value lines, suitable for appending to $GITHUB_ENV:
#
#   TORNADO_SPEC=/path/to/tornado-6.6.dev1-cp39-abi3-...whl
#   TORNADO_EXPECT_VERSION=6.6.dev1
#
# Prefers a wheel over an sdist (that is what users install), and prefers a
# pure-python/abi3 wheel for the current platform. Exits non-zero if the
# directory holds nothing usable, because silently falling back to PyPI's
# tornado would make the whole run meaningless.
set -euo pipefail

usage() { echo "usage: $0 <artifact-dir>" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
dir="$1"

[[ -d "${dir}" ]] || { echo "no such directory: ${dir}" >&2; exit 1; }

# A wheel built for this interpreter/platform, else any wheel, else the sdist.
# `uv pip install` will reject a wheel that does not match the platform, so a
# wrong pick fails loudly rather than quietly testing the wrong thing.
mapfile -t candidates < <(
    find "${dir}" -maxdepth 2 -type f \( -name 'tornado-*.whl' -o -name 'tornado-*.tar.gz' \) \
        | sort
)
if [[ "${#candidates[@]}" -eq 0 ]]; then
    echo "no tornado wheel or sdist found under ${dir}" >&2
    find "${dir}" -maxdepth 2 -type f -printf '  %p\n' >&2 || true
    exit 1
fi

spec=""
for pattern in '*abi3*manylinux*x86_64*.whl' '*abi3*.whl' '*none-any.whl' '*.whl' '*.tar.gz'; do
    for candidate in "${candidates[@]}"; do
        # shellcheck disable=SC2053  # glob match is intended
        if [[ "$(basename "${candidate}")" == ${pattern} ]]; then
            spec="${candidate}"
            break 2
        fi
    done
done
[[ -n "${spec}" ]] || { echo "could not choose an artifact from ${dir}" >&2; exit 1; }

# Both wheel and sdist names put the version in the second '-'-separated field
# (PEP 427 / PEP 625), already PEP 440 normalized.
base="$(basename "${spec}")"
case "${base}" in
    *.whl)    version="$(echo "${base}" | cut -d- -f2)" ;;
    *.tar.gz) version="${base#tornado-}"; version="${version%.tar.gz}" ;;
esac

if [[ -z "${version}" ]]; then
    echo "could not read a version out of ${base}" >&2
    exit 1
fi

echo "TORNADO_SPEC=${spec}"
echo "TORNADO_EXPECT_VERSION=${version}"

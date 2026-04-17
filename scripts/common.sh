#!/usr/bin/env bash
# Shared helpers for setup / run scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="${ROOT_DIR}/packages"
LOGS_DIR="${ROOT_DIR}/logs"
RESULTS_DIR="${ROOT_DIR}/results"
MANIFEST="${ROOT_DIR}/packages.json"

mkdir -p "${PACKAGES_DIR}" "${LOGS_DIR}" "${RESULTS_DIR}"

# Read JSON field for package at index $1, key $2 using python.
# Returns empty string (exit 0) for missing keys.
pkg_field() {
    local idx="$1" key="$2"
    python3 -c "
import json, sys
with open('${MANIFEST}') as f:
    m = json.load(f)
print(m['packages'][${idx}].get('${key}', ''))
"
}

pkg_count() {
    python3 -c "
import json
with open('${MANIFEST}') as f:
    print(len(json.load(f)['packages']))
"
}

#!/usr/bin/env bash
# Generate HTML coverage reports for each package and a merged report.
# Run this after scripts/run_all.sh (or run_one.sh) has produced coverage data
# in coverage/<name>.coverage.
#
# Outputs:
#   coverage_html/<name>/   — per-package report, tornado library files only
#   coverage_html/merged/   — union of all packages, path-remapped to a single
#                             canonical tornado installation
set -uo pipefail
source "$(dirname "$0")/common.sh"

REPORTS_DIR="${ROOT_DIR}/coverage_html"
COV_DIR="${ROOT_DIR}/coverage"

# tornado/test/ contains tornado's own test suite.  It's part of the tornado
# package so --cov=tornado picks it up, but every package has 0% coverage on
# those files (no downstream test runs tornado's own tests).  Omitting them
# keeps the reports focused on the library code that packages actually use.
OMIT_PATTERN="*/tornado/test/*"

mkdir -p "${REPORTS_DIR}"

N="$(pkg_count)"
canonical_tornado=""   # set on first successful package

# ── per-package reports ─────────────────────────────────────────────────────
for ((i = 0; i < N; i++)); do
    name="$(pkg_field "$i" name)"
    cov_file="${COV_DIR}/${name}.coverage"
    venv="${PACKAGES_DIR}/${name}/.venv"

    if [[ ! -f "${cov_file}" ]]; then
        echo "⚠  No coverage data for ${name} (expected ${cov_file}), skipping"
        continue
    fi
    if [[ ! -d "${venv}" ]]; then
        echo "⚠  No venv for ${name}, skipping"
        continue
    fi

    echo "=== ${name} ==="
    # shellcheck disable=SC1091
    source "${venv}/bin/activate"

    # Capture the canonical tornado path from the first working venv.
    if [[ -z "${canonical_tornado}" ]]; then
        canonical_tornado="$(python -c \
            'import tornado, os; print(os.path.dirname(tornado.__file__))')"
        echo "Canonical tornado source: ${canonical_tornado}"
    fi

    rm -rf "${REPORTS_DIR}/${name}"
    coverage html \
        --data-file="${cov_file}" \
        --rcfile=/dev/null \
        --omit="${OMIT_PATTERN}" \
        -d "${REPORTS_DIR}/${name}" \
        --title="${name} — tornado coverage" \
        2>&1 | grep -v "^$" || echo "  (no output)"

    deactivate || true
done

# ── merged report ────────────────────────────────────────────────────────────
echo ""
echo "=== merged ==="

if [[ -z "${canonical_tornado}" ]]; then
    echo "ERROR: no coverage data found, cannot build merged report" >&2
    exit 1
fi

# Build a coverage config that remaps every package's tornado installation
# to the canonical path so coverage combine treats them as the same source.
MERGE_CFG="${COV_DIR}/.coveragerc-merge"
{
    echo "[paths]"
    echo "tornado ="
    # Canonical path first (coverage.py uses it as the target).
    echo "    ${canonical_tornado}"
    # Glob pattern that matches any package's site-packages tornado directory.
    echo "    */site-packages/tornado"
    echo ""
    # [run] omit applies during collection; [report] omit applies during reporting.
    echo "[report]"
    echo "omit = ${OMIT_PATTERN}"
} > "${MERGE_CFG}"

MERGED_COV="${COV_DIR}/merged.coverage"

# Collect all per-package coverage files that exist.
cov_files=()
for ((i = 0; i < N; i++)); do
    name="$(pkg_field "$i" name)"
    f="${COV_DIR}/${name}.coverage"
    [[ -f "${f}" ]] && cov_files+=("${f}")
done

# shellcheck disable=SC1091
source "${PACKAGES_DIR}/$(pkg_field 0 name)/.venv/bin/activate"

COVERAGE_FILE="${MERGED_COV}" coverage combine \
    --rcfile="${MERGE_CFG}" \
    --keep \
    "${cov_files[@]}" 2>&1

rm -rf "${REPORTS_DIR}/merged"
mkdir -p "${REPORTS_DIR}/merged"
coverage html \
    --data-file="${MERGED_COV}" \
    --rcfile=/dev/null \
    --omit="${OMIT_PATTERN}" \
    -d "${REPORTS_DIR}/merged" \
    --title="All packages — tornado coverage (merged)" \
    2>&1 | grep -v "^$"

deactivate || true

echo ""
echo "Reports written to ${REPORTS_DIR}/"

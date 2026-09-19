#!/usr/bin/env bash
# Generate HTML coverage reports for each package and a merged report.
# Run after run_all.sh / run_one.sh has produced coverage/<name>.coverage, or in
# CI over per-package coverage artifacts downloaded into the same place.
#
# Outputs:
#   coverage_html/<name>/   — per-package report, tornado library files only
#   coverage_html/merged/   — union of all packages, path-remapped to a single
#                             canonical tornado installation
#
# Every package records coverage against its own venv's copy of tornado, so all
# rendering goes through `coverage combine` with a [paths] remap that collapses
# those copies onto one canonical tornado. That is what lets this run somewhere
# the per-package venvs do not exist -- the job matrix uploads the .coverage
# files but nothing else, so there is nothing to render against until the remap
# has pointed them all at a tornado this machine actually has.
#
# Inputs (environment):
#   TORNADO_SPEC  Which tornado to install into the report venv, when one has to
#                 be built. Must be the same tornado the packages ran against or
#                 the annotated HTML will not line up with the recorded data.
set -uo pipefail
source "$(dirname "$0")/common.sh"

REPORTS_DIR="${ROOT_DIR}/coverage_html"
COV_DIR="${ROOT_DIR}/coverage"
REPORT_VENV="${COV_DIR}/.report-venv"
TORNADO_SPEC="${TORNADO_SPEC:-tornado}"

mkdir -p "${REPORTS_DIR}" "${COV_DIR}"
mapfile -t names < <(pkg_names)

# ── the environment reports are rendered with ────────────────────────────────
# Needs two things: coverage installed, and tornado source on disk to annotate.
# A local serial run already has both in every package venv; the matrix path has
# neither, so build one.
COV_PY=""
for name in "${names[@]}"; do
    candidate="${CHECKOUTS_DIR}/${name}/.venv/bin/python"
    if [[ -x "${candidate}" ]] && "${candidate}" -c 'import coverage, tornado' 2>/dev/null; then
        COV_PY="${candidate}"
        echo "Rendering with ${name}'s venv"
        break
    fi
done

if [[ -z "${COV_PY}" ]]; then
    echo "No package venv available; building a report venv for ${TORNADO_SPEC}"
    rm -rf "${REPORT_VENV}"
    if ! uv venv --python "${PYTHON_VERSION}" "${REPORT_VENV}" >/dev/null 2>&1; then
        echo "ERROR: could not create the report venv" >&2
        exit 1
    fi
    if ! uv pip install --python "${REPORT_VENV}/bin/python" -q coverage "${TORNADO_SPEC}"; then
        echo "ERROR: could not install coverage and ${TORNADO_SPEC} into the report venv" >&2
        exit 1
    fi
    COV_PY="${REPORT_VENV}/bin/python"
fi

canonical_tornado="$("${COV_PY}" -c 'import tornado, os; print(os.path.dirname(tornado.__file__))')"
if [[ -z "${canonical_tornado}" || ! -d "${canonical_tornado}" ]]; then
    echo "ERROR: no tornado source to render against" >&2
    exit 1
fi
echo "Canonical tornado source: ${canonical_tornado}"

# Remap config: every package's own site-packages tornado is rewritten to the
# canonical one, so data recorded in nine different venvs describes one library.
MERGE_CFG="${COV_DIR}/.coveragerc-merge"
{
    echo "[paths]"
    echo "tornado ="
    # Canonical path first — coverage.py uses it as the target.
    echo "    ${canonical_tornado}"
    # Matches any package's site-packages tornado directory.
    echo "    */site-packages/tornado"
    echo ""
    # [run] omit applies during collection; [report] omit applies during reporting.
    echo "[report]"
    echo "omit = ${COVERAGE_OMIT}"
} > "${MERGE_CFG}"

# remap <source-data-file> <output-data-file>
# Rewrites recorded paths onto the canonical tornado. --keep leaves the input
# alone so a rerun still has something to work from.
remap() {
    rm -f "$2"
    COVERAGE_FILE="$2" "${COV_PY}" -m coverage combine \
        --rcfile="${MERGE_CFG}" --keep "$1" >/dev/null 2>&1
}

# render <data-file> <output-dir> <title>
render() {
    rm -rf "${2:?}"
    "${COV_PY}" -m coverage html \
        --data-file="$1" \
        --rcfile=/dev/null \
        --omit="${COVERAGE_OMIT}" \
        -d "$2" \
        --title="$3" \
        2>&1 | grep -v "^$" || echo "  (no output)"
}

# Drop report directories for packages that no longer exist. A stale report is
# worse than a missing one: it keeps publishing coverage for a package that was
# removed, and nothing about the page says it is out of date.
for existing in "${REPORTS_DIR}"/*/; do
    [[ -d "${existing}" ]] || continue
    stale_name="$(basename "${existing}")"
    [[ "${stale_name}" == "merged" ]] && continue
    if [[ ! -d "${PKGDEFS_DIR}/${stale_name}" ]]; then
        echo "Removing stale report for ${stale_name} (no longer a package)"
        rm -rf "${REPORTS_DIR:?}/${stale_name}"
    fi
done

# ── per-package reports ─────────────────────────────────────────────────────
cov_files=()
for name in "${names[@]}"; do
    cov_file="${COV_DIR}/${name}.coverage"
    if [[ ! -f "${cov_file}" ]]; then
        echo "⚠  No coverage data for ${name} (expected ${cov_file}), skipping"
        continue
    fi
    cov_files+=("${cov_file}")

    echo "=== ${name} ==="
    remapped="${COV_DIR}/.remapped-${name}.coverage"
    if ! remap "${cov_file}" "${remapped}"; then
        echo "⚠  Could not remap ${name}'s coverage data, skipping"
        continue
    fi
    render "${remapped}" "${REPORTS_DIR}/${name}" "${name} — tornado coverage"
    rm -f "${remapped}"
done

# ── merged report ────────────────────────────────────────────────────────────
echo ""
echo "=== merged ==="

if [[ "${#cov_files[@]}" -eq 0 ]]; then
    echo "ERROR: no coverage data found, cannot build merged report" >&2
    exit 1
fi

MERGED_COV="${COV_DIR}/merged.coverage"
rm -f "${MERGED_COV}"
COVERAGE_FILE="${MERGED_COV}" "${COV_PY}" -m coverage combine \
    --rcfile="${MERGE_CFG}" \
    --keep \
    "${cov_files[@]}" 2>&1

render "${MERGED_COV}" "${REPORTS_DIR}/merged" "All packages — tornado coverage (merged)"

echo ""
echo "Reports written to ${REPORTS_DIR}/"

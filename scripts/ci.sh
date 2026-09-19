#!/usr/bin/env bash
# Run the full testbed on one machine, for automated runs and for local use.
#
# The GitHub workflow normally runs packages as a job matrix and calls
# scripts/report.sh itself; this script is the serial equivalent, and the only
# path that can also build HTML coverage reports (those need each package's venv,
# which does not survive a matrix job).
#
# It never writes anything back into git history: results are surfaced via
# stdout, the GitHub step summary, and the files left in logs/ results/
# coverage_html/ for the caller to upload.
#
# Inputs (environment):
#   TORNADO_SPEC  What to test against. Anything `uv pip install` accepts:
#                   - a release pin        "tornado==6.5.1"
#                   - a local checkout      "/path/to/tornado"
#                   - a built wheel         "/path/to/tornado-7.0-py3-none-any.whl"
#                   - a branch/tag/SHA      "git+https://github.com/tornadoweb/tornado.git@BRANCH"
#                 Defaults to "tornado" (latest PyPI release).
#   ONLY          Optional space-separated list of package names/ranks to run
#                 instead of everything.
#   COVERAGE      "1" (default) measures coverage and builds HTML reports.
#   FAIL_ON_REGRESSION
#                 "1" (default) exits non-zero unless every package passed, so
#                 this can be used as a release gate. "0" reports only.
set -uo pipefail
source "$(dirname "$0")/common.sh"

export TORNADO_SPEC="${TORNADO_SPEC:-tornado}"
export COVERAGE="${COVERAGE:-1}"

group()    { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::group::$*" || echo "=== $* ==="; }
endgroup() { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::endgroup::" || true; }

# Malformed definitions should stop the run immediately rather than surface as a
# mystery failure twenty minutes in.
python3 "${ROOT_DIR}/scripts/validate_packages.py" || exit 2

echo "Testing downstream packages against TORNADO_SPEC=${TORNADO_SPEC}"

# Start from a clean slate. Results are what this run measured, not a union with
# whatever a previous run left behind -- otherwise a stale results/<name>.txt
# counts toward the gate, which bites hardest on ONLY= runs.
rm -f "${RESULTS_DIR}"/*.txt "${LOGS_DIR}"/*.log

if [[ -n "${ONLY:-}" ]]; then
    # shellcheck disable=SC2086  # intentional word-split on ${ONLY}
    group "setup: clone selected packages"
    # shellcheck disable=SC2086
    bash "${ROOT_DIR}/scripts/setup.sh" ${ONLY}
    endgroup

    for sel in ${ONLY}; do
        group "run: ${sel}"
        bash "${ROOT_DIR}/scripts/run_one.sh" "${sel}" || true
        endgroup
    done
    bash "${ROOT_DIR}/scripts/summarize.sh"
else
    group "setup: clone downstream packages"
    bash "${ROOT_DIR}/scripts/setup.sh"
    endgroup

    group "run: all packages"
    bash "${ROOT_DIR}/scripts/run_all.sh"
    endgroup
fi

# Coverage reports are best-effort: a failed report build must not mask the
# actual test results the run already produced.
if [[ "${COVERAGE}" == "1" ]]; then
    group "coverage: build HTML reports"
    bash "${ROOT_DIR}/scripts/gen_reports.sh" || echo "WARNING: coverage report generation failed"
    endgroup
fi

# report.sh renders the summary, echoes failing logs, and owns the exit code.
# The workflow's matrix path calls the same script, so the two cannot disagree
# about whether a run passed.
exec bash "${ROOT_DIR}/scripts/report.sh"

#!/usr/bin/env bash
# Run the test suite for a single package (by index or name) in an isolated
# uv-managed virtualenv. Each invocation:
#   1. Creates a fresh .venv under the checkout
#   2. Installs the package (editable with its test extras, or the pinned wheel)
#   3. Runs the package's optional setup.sh hook
#   4. Force-installs the Tornado under test (TORNADO_SPEC)
#   5. Runs the package's test.sh, streaming output to a log
#   6. Verifies the Tornado under test is still the one that was installed
# Exits with the test command's exit code, or one of the status codes below.
#
# Because this script is the thing a release gate believes, every step that
# could make the run test the *wrong* Tornado is a hard failure rather than a
# warning: a green run has to mean "the requested Tornado passed", not "some
# Tornado passed".
#
# Inputs (environment):
#   TORNADO_SPEC            What to test against (any `uv pip install` spec).
#   TORNADO_EXPECT_VERSION  Optional. If set, the installed tornado.version must
#                           match exactly, else the package fails as
#                           TORNADO_MISMATCH. Set by ci.sh when the spec is a
#                           wheel/sdist whose filename names the version.
#   TIMEOUT_SECS            Per-package wall-clock limit (default 900).
#   PYTHON_VERSION          Interpreter for the venv (default 3.13, matching
#                           tornado's own default_python_minor). Current
#                           downstream releases are already dropping older
#                           interpreters -- bokeh 3.10 requires >=3.12 -- so this
#                           needs to track what the ecosystem builds against.
#   RETRY_TIMEOUT           Re-run once on timeout (default 1). The real-kernel
#                           ZeroMQ suites deadlock intermittently; see REPORT.md.
#   COVERAGE                "1" (default) measures Tornado coverage. When "0",
#                           COV_ARGS is exported empty so each package's test.sh
#                           drops its --cov flags and pytest-cov is not installed.
#                           When measuring, a package that declares min_coverage
#                           in package.env fails as COVERAGE_LOW if it comes in
#                           under that floor -- the signal that a test command
#                           has stopped exercising Tornado rather than that
#                           Tornado broke.
#
# Statuses / exit codes:
#   PASS                   0
#   FAIL                   test command's own non-zero code
#   TIMEOUT                124
#   INSTALL_FAIL           3   package (not tornado) failed to install
#   SETUP_FAIL             4   venv creation or the package's setup.sh failed
#   TORNADO_INSTALL_FAIL   5   the Tornado under test would not install
#   TORNADO_MISMATCH       6   the env does not hold the Tornado under test
#   COVERAGE_LOW           7   tests passed but exercised too little of Tornado
set -uo pipefail
source "$(dirname "$0")/common.sh"

TORNADO_SPEC="${TORNADO_SPEC:-tornado}"   # e.g. TORNADO_SPEC="tornado==6.5.1"
TORNADO_EXPECT_VERSION="${TORNADO_EXPECT_VERSION:-}"
TIMEOUT_SECS="${TIMEOUT_SECS:-900}"
RETRY_TIMEOUT="${RETRY_TIMEOUT:-1}"

usage() {
    echo "usage: $0 <name-or-rank>" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage

# Resolve the selector and load the package's definition in one step.
name="$(pkg_resolve "$1")" || exit 2
eval "$(pkg_load "${name}")"

checkout="${CHECKOUTS_DIR}/${name}"
work="${checkout}/${PKG_SUBDIR}"
log="${LOGS_DIR}/${name}.log"
result="${RESULTS_DIR}/${name}.txt"

# Populated as the run progresses so write_result can always emit a full record.
install_start=0
install_secs=0
test_secs=0
attempts=0
tornado_ver="n/a"
tornado_file="n/a"
tornado_after="n/a"
coverage_pct="n/a"

# write_result <status> <exit_code>
# Single writer for results/<name>.txt so every exit path emits the same schema.
write_result() {
    {
        echo "package=${name}"
        echo "status=$1"
        echo "exit_code=$2"
        echo "tornado=${tornado_ver}"
        echo "tornado_file=${tornado_file}"
        echo "tornado_after=${tornado_after}"
        echo "coverage_pct=${coverage_pct}"
        echo "install_secs=${install_secs}"
        echo "test_secs=${test_secs}"
        echo "attempts=${attempts}"
    } > "${result}"
}

# die <status> <exit_code> <message>
die() {
    echo "$3" | tee -a "${log}"
    write_result "$1" "$2"
    deactivate 2>/dev/null || true
    echo "Result: $1"
    exit "$2"
}

# Report the tornado currently importable in the venv: "<version>|<path>".
# Prints "unknown|unknown" rather than failing so callers can treat a broken
# env as a mismatch instead of crashing.
probe_tornado() {
    python -c 'import tornado, sys; sys.stdout.write(tornado.version + "|" + tornado.__file__)' \
        2>/dev/null || echo "unknown|unknown"
}

if [[ ! -d "${work}" ]]; then
    echo "Package ${name} not checked out; run scripts/setup.sh ${name} first." >&2
    exit 2
fi

echo "=== ${name} ===" | tee "${log}"
echo "Working dir:  ${work}" | tee -a "${log}"
echo "Version:      ${PKG_DIST_NAME}==${PKG_VERSION} (ref ${PKG_REF})" | tee -a "${log}"
echo "Test script:  ${PKG_TEST_SH}" | tee -a "${log}"
echo "Tornado:      ${TORNADO_SPEC}" | tee -a "${log}"
[[ -n "${TORNADO_EXPECT_VERSION}" ]] && \
    echo "Expecting:    tornado ${TORNADO_EXPECT_VERSION}" | tee -a "${log}"
echo "Python:       ${PYTHON_VERSION}" | tee -a "${log}"
echo "Timeout:      ${TIMEOUT_SECS}s" | tee -a "${log}"
echo "" | tee -a "${log}"

install_start=$(date +%s)

venv="${checkout}/.venv"
rm -rf "${venv}"
# An unchecked `uv venv` used to leave the `source` below failing, which under
# `set +e` meant the suite ran against the system python.
if ! uv venv --python "${PYTHON_VERSION}" "${venv}" >>"${log}" 2>&1; then
    install_secs=$(( $(date +%s) - install_start ))
    die SETUP_FAIL 4 "Failed to create venv with python ${PYTHON_VERSION}"
fi
# shellcheck disable=SC1091
if ! source "${venv}/bin/activate"; then
    install_secs=$(( $(date +%s) - install_start ))
    die SETUP_FAIL 4 "Failed to activate ${venv}"
fi

# Install the package.
install_ok=0
if [[ "${PKG_INSTALL_METHOD}" == "pypi" ]]; then
    # Install the published wheel (for packages whose source build requires a JS
    # toolchain or network-fetched assets). Tests still run from the cloned
    # source tree, but against the site-packages version. requirements.txt is
    # the same pin the checkout's ref was derived from.
    echo ">>> PyPI install: uv pip install -r ${PKG_REQUIREMENTS}" >>"${log}"
    if uv pip install -r "${PKG_REQUIREMENTS}" >>"${log}" 2>&1; then
        install_ok=1
        if [[ -n "${PKG_PYPI_EXTRA_DEPS}" ]]; then
            echo ">>> Extra deps: ${PKG_PYPI_EXTRA_DEPS}" >>"${log}"
            # shellcheck disable=SC2086  # intentional word-split
            uv pip install ${PKG_PYPI_EXTRA_DEPS} >>"${log}" 2>&1 || install_ok=0
        fi
    fi
else
    # Try editable with common test-extra names.
    for extras in "test" "tests" "dev" "testing" ""; do
        suffix=""
        [[ -n "${extras}" ]] && suffix="[${extras}]"
        echo ">>> Trying: uv pip install -e \".${suffix}\"" >>"${log}"
        if (cd "${work}" && uv pip install -e ".${suffix}") >>"${log}" 2>&1; then
            install_ok=1
            echo ">>> Installed with extras=${extras:-<none>}" >>"${log}"
            break
        fi
    done
fi

if [[ "${install_ok}" -ne 1 ]]; then
    install_secs=$(( $(date +%s) - install_start ))
    die INSTALL_FAIL 3 "INSTALL FAILED"
fi

# Optional per-package post-install step (protoc codegen, etc).
# Runs after package installation so that dep resolution (e.g. protobuf version)
# is constrained by what the package already requires.
if [[ -n "${PKG_SETUP_SH}" ]]; then
    echo ">>> setup hook: ${PKG_SETUP_SH}" >>"${log}"
    if ! (cd "${work}" && bash "${PKG_SETUP_SH}") >>"${log}" 2>&1; then
        install_secs=$(( $(date +%s) - install_start ))
        die SETUP_FAIL 4 "setup.sh failed"
    fi
fi

# Test runner is always pytest. pytest-cov is only needed when measuring, and a
# gate run does not measure.
if [[ "${COVERAGE:-1}" == "1" ]]; then
    uv pip install pytest pytest-cov >>"${log}" 2>&1 || true
else
    uv pip install pytest >>"${log}" 2>&1 || true
    # Each package's test.sh defaults COV_ARGS to its own --cov flags; exporting
    # it empty is how the harness turns coverage off.
    export COV_ARGS=""
fi

# Force the Tornado we want to test against. This must be a hard failure: a
# typo'd spec or a dead git ref would otherwise leave the downstream resolver's
# own tornado in place and report PASS for a Tornado we never tested.
if ! uv pip install --upgrade "${TORNADO_SPEC}" >>"${log}" 2>&1; then
    install_secs=$(( $(date +%s) - install_start ))
    die TORNADO_INSTALL_FAIL 5 "Failed to install ${TORNADO_SPEC}"
fi

IFS='|' read -r tornado_ver tornado_file <<<"$(probe_tornado)"
echo "Tornado in env: ${tornado_ver} (${tornado_file})" | tee -a "${log}"

if [[ "${tornado_ver}" == "unknown" ]]; then
    install_secs=$(( $(date +%s) - install_start ))
    die TORNADO_MISMATCH 6 "Installed ${TORNADO_SPEC} but tornado is not importable"
fi
if [[ -n "${TORNADO_EXPECT_VERSION}" && "${tornado_ver}" != "${TORNADO_EXPECT_VERSION}" ]]; then
    install_secs=$(( $(date +%s) - install_start ))
    die TORNADO_MISMATCH 6 \
        "Expected tornado ${TORNADO_EXPECT_VERSION} but env has ${tornado_ver}"
fi

install_end=$(date +%s)
install_secs=$((install_end - install_start))
echo "Install took ${install_secs}s" | tee -a "${log}"
echo "" | tee -a "${log}"
echo "--- test output ---" | tee -a "${log}"

# Save coverage data to a canonical per-package path so gen_reports.sh can find it.
mkdir -p "${ROOT_DIR}/coverage"
export COVERAGE_FILE="${ROOT_DIR}/coverage/${name}.coverage"

run_tests() {
    (cd "${work}" && timeout "${TIMEOUT_SECS}" bash "${PKG_TEST_SH}") >>"${log}" 2>&1
}

# common.sh turns on `set -e`, so every invocation of the test command has to be
# guarded: an unguarded `run_tests` aborts this script on the first failing
# suite, before any result file is written, which makes a red package invisible
# to the gate in ci.sh. `|| rc=$?` keeps the failure a value we handle.
test_start=$(date +%s)
attempts=1
rc=0
run_tests || rc=$?
# Retry once on timeout only. The real-kernel (ZeroMQ) suites deadlock
# intermittently in a poll that ignores SIGALRM and SIGTERM (see REPORT.md), so
# a timeout is the one status worth a second look. A genuine failure is not
# retried: re-running red tests to see if they go green is how a gate loses its
# meaning.
if [[ "${rc}" -eq 124 && "${RETRY_TIMEOUT}" == "1" ]]; then
    echo "" | tee -a "${log}"
    echo "--- timed out after ${TIMEOUT_SECS}s; retrying once ---" | tee -a "${log}"
    attempts=2
    rc=0
    run_tests || rc=$?
fi
test_end=$(date +%s)
test_secs=$((test_end - test_start))

echo "" | tee -a "${log}"
echo "exit_code=${rc}" | tee -a "${log}"
echo "test_runtime_secs=${test_secs}" | tee -a "${log}"

# Several test commands install more packages mid-run (bokeh and distributed
# both `uv pip install` inside their test command), so a transitive `tornado<X`
# pin can quietly downgrade the thing under test after we verified it. A result
# measured against a different Tornado than the one requested is not a result.
IFS='|' read -r tornado_after _ <<<"$(probe_tornado)"
if [[ "${tornado_after}" != "${tornado_ver}" ]]; then
    die TORNADO_MISMATCH 6 \
        "Tornado changed during the run: ${tornado_ver} -> ${tornado_after}"
fi

status="PASS"
if [[ "${rc}" -eq 124 ]]; then
    status="TIMEOUT"
elif [[ "${rc}" -ne 0 ]]; then
    status="FAIL"
fi

# How much of Tornado this package actually exercised. Measured whenever we have
# the data, because it is worth seeing in the summary either way.
if [[ "${COVERAGE:-1}" == "1" && -f "${COVERAGE_FILE}" ]]; then
    measured="$(python -m coverage report \
        --data-file="${COVERAGE_FILE}" \
        --rcfile=/dev/null \
        --omit="${COVERAGE_OMIT}" \
        --format=total 2>/dev/null)"
    # A non-numeric answer means coverage could not read the data; leave the
    # recorded value as n/a rather than inventing a number to compare against.
    [[ "${measured}" =~ ^[0-9]+$ ]] && coverage_pct="${measured}"
    echo "Tornado coverage: ${coverage_pct}%" | tee -a "${log}"
fi

# The floor is only meaningful when coverage was actually requested and the
# suite ran to completion. Checking it with COVERAGE=0 would fail every package
# on the release gate, which deliberately does not measure; and on a failing or
# timed-out run the low coverage is explained by the failure, so reporting
# COVERAGE_LOW there would bury the real one.
if [[ "${COVERAGE:-1}" == "1" && "${status}" == "PASS" && -n "${PKG_MIN_COVERAGE}" ]]; then
    if [[ "${coverage_pct}" == "n/a" ]]; then
        die COVERAGE_LOW 7 \
            "${name} declares min_coverage=${PKG_MIN_COVERAGE}% but no coverage was measured"
    fi
    if [[ "${coverage_pct}" -lt "${PKG_MIN_COVERAGE}" ]]; then
        die COVERAGE_LOW 7 \
            "Tornado coverage ${coverage_pct}% is below ${name}'s floor of ${PKG_MIN_COVERAGE}%. The tests passed, so this says the test command stopped exercising Tornado rather than that Tornado broke."
    fi
fi

write_result "${status}" "${rc}"

deactivate 2>/dev/null || true
echo "Result: ${status}"
exit "${rc}"

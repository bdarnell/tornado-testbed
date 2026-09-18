#!/usr/bin/env bash
# Run the test suite for a single package (by index or name) in an isolated
# uv-managed virtualenv. Each invocation:
#   1. Creates a fresh .venv under the package directory
#   2. Installs the package with its test extras (pip install ".[test]")
#   3. Force-installs the Tornado under test (TORNADO_SPEC)
#   4. Runs the test command from the manifest, streaming output to a log
#   5. Verifies the Tornado under test is still the one that was installed
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
#   PYTHON_VERSION          Interpreter for the venv (default 3.11).
#   RETRY_TIMEOUT           Re-run once on timeout (default 1). The real-kernel
#                           ZeroMQ suites deadlock intermittently; see REPORT.md.
#
# Statuses / exit codes:
#   PASS                   0
#   FAIL                   test command's own non-zero code
#   TIMEOUT                124
#   INSTALL_FAIL           3   package (not tornado) failed to install
#   SETUP_FAIL             4   venv creation or the setup_extra hook failed
#   TORNADO_INSTALL_FAIL   5   the Tornado under test would not install
#   TORNADO_MISMATCH       6   the env does not hold the Tornado under test
set -uo pipefail
source "$(dirname "$0")/common.sh"

TORNADO_SPEC="${TORNADO_SPEC:-tornado}"   # e.g. TORNADO_SPEC="tornado==6.5.1"
TORNADO_EXPECT_VERSION="${TORNADO_EXPECT_VERSION:-}"
TIMEOUT_SECS="${TIMEOUT_SECS:-900}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
RETRY_TIMEOUT="${RETRY_TIMEOUT:-1}"

usage() {
    echo "usage: $0 <index-or-name>" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
SEL="$1"

# Resolve selector -> index.
N="$(pkg_count)"
idx=""
if [[ "${SEL}" =~ ^[0-9]+$ ]]; then
    idx="${SEL}"
else
    for ((i = 0; i < N; i++)); do
        if [[ "$(pkg_field "$i" name)" == "${SEL}" ]]; then
            idx="$i"; break
        fi
    done
fi
[[ -n "${idx}" ]] || { echo "Unknown package: ${SEL}" >&2; exit 2; }

name="$(pkg_field "${idx}" name)"
subdir="$(pkg_field "${idx}" subdir)"
test_cmd="$(pkg_field "${idx}" test_cmd)"
setup_extra="$(pkg_field "${idx}" setup_extra)"
install_method="$(pkg_field "${idx}" install_method)"  # "" (default=editable) or "pypi"
pypi_spec="$(pkg_field "${idx}" pypi_spec)"            # e.g. "panel==1.5.3"
pkg_root="${PACKAGES_DIR}/${name}"
work="${pkg_root}/${subdir}"
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
    echo "Package ${name} not set up; run scripts/setup.sh first." >&2
    exit 2
fi

echo "=== ${name} ===" | tee "${log}"
echo "Working dir:  ${work}" | tee -a "${log}"
echo "Test command: ${test_cmd}" | tee -a "${log}"
echo "Tornado:      ${TORNADO_SPEC}" | tee -a "${log}"
[[ -n "${TORNADO_EXPECT_VERSION}" ]] && \
    echo "Expecting:    tornado ${TORNADO_EXPECT_VERSION}" | tee -a "${log}"
echo "Python:       ${PYTHON_VERSION}" | tee -a "${log}"
echo "Timeout:      ${TIMEOUT_SECS}s" | tee -a "${log}"
echo "" | tee -a "${log}"

install_start=$(date +%s)

venv="${pkg_root}/.venv"
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
if [[ "${install_method}" == "pypi" ]]; then
    # Install the published wheel (for packages whose source build requires
    # a JS toolchain or network-fetched assets). Run tests from the cloned
    # source tree, but against the site-packages version.
    echo ">>> Trying PyPI install: uv pip install ${pypi_spec}" >>"${log}"
    # shellcheck disable=SC2086  # intentional word-split on ${pypi_spec}
    if uv pip install ${pypi_spec} >>"${log}" 2>&1; then
        install_ok=1
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
if [[ -n "${setup_extra}" ]]; then
    echo ">>> setup_extra: ${setup_extra}" >>"${log}"
    if ! (cd "${work}" && bash -c "${setup_extra}") >>"${log}" 2>&1; then
        install_secs=$(( $(date +%s) - install_start ))
        die SETUP_FAIL 4 "setup_extra failed"
    fi
fi

# Test runner is almost always pytest; make sure it and coverage are available.
uv pip install pytest pytest-cov >>"${log}" 2>&1 || true

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
    (cd "${work}" && timeout "${TIMEOUT_SECS}" bash -c "${test_cmd}") >>"${log}" 2>&1
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

write_result "${status}" "${rc}"

deactivate 2>/dev/null || true
echo "Result: ${status}"
exit "${rc}"

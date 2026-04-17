#!/usr/bin/env bash
# Run the test suite for a single package (by index or name) in an isolated
# uv-managed virtualenv. Each invocation:
#   1. Creates a fresh .venv under the package directory
#   2. Installs the package with its test extras (pip install ".[test]")
#   3. Installs the pinned Tornado from PyPI (so we're testing against a real
#      release rather than whatever their resolver picks)
#   4. Runs the test command from the manifest, streaming output to a log
# Exits with the test command's exit code.
set -uo pipefail
source "$(dirname "$0")/common.sh"

TORNADO_SPEC="${TORNADO_SPEC:-tornado}"   # e.g. TORNADO_SPEC="tornado==6.5.1"
TIMEOUT_SECS="${TIMEOUT_SECS:-900}"

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

if [[ ! -d "${work}" ]]; then
    echo "Package ${name} not set up; run scripts/setup.sh first." >&2
    exit 2
fi

echo "=== ${name} ===" | tee "${log}"
echo "Working dir:  ${work}" | tee -a "${log}"
echo "Test command: ${test_cmd}" | tee -a "${log}"
echo "Tornado:      ${TORNADO_SPEC}" | tee -a "${log}"
echo "Timeout:      ${TIMEOUT_SECS}s" | tee -a "${log}"
echo "" | tee -a "${log}"

venv="${pkg_root}/.venv"
rm -rf "${venv}"
uv venv --python 3.11 "${venv}" >>"${log}" 2>&1
# shellcheck disable=SC1091
source "${venv}/bin/activate"

install_start=$(date +%s)

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
    echo "INSTALL FAILED" | tee -a "${log}"
    {
        echo "package=${name}"
        echo "status=INSTALL_FAIL"
        echo "exit_code=3"
        echo "tornado=n/a"
        echo "install_secs=$(( $(date +%s) - install_start ))"
        echo "test_secs=0"
    } > "${result}"
    deactivate || true
    exit 3
fi

# Optional per-package post-install step (protoc codegen, etc).
# Runs after package installation so that dep resolution (e.g. protobuf version)
# is constrained by what the package already requires.
if [[ -n "${setup_extra}" ]]; then
    echo ">>> setup_extra: ${setup_extra}" >>"${log}"
    if ! (cd "${work}" && bash -c "${setup_extra}") >>"${log}" 2>&1; then
        echo "setup_extra failed" | tee -a "${log}"
        {
            echo "package=${name}"
            echo "status=SETUP_FAIL"
            echo "exit_code=4"
            echo "tornado=n/a"
            echo "install_secs=$(( $(date +%s) - install_start ))"
            echo "test_secs=0"
        } > "${result}"
        deactivate || true
        exit 4
    fi
fi

# Test runner is almost always pytest; make sure it and coverage are available.
uv pip install pytest pytest-cov >>"${log}" 2>&1 || true

# Force the Tornado we want to test against.
uv pip install --upgrade "${TORNADO_SPEC}" >>"${log}" 2>&1 || {
    echo "Failed to install ${TORNADO_SPEC}" | tee -a "${log}"
}
tornado_ver="$(python -c 'import tornado, sys; sys.stdout.write(tornado.version)' 2>/dev/null || echo 'unknown')"
echo "Tornado in env: ${tornado_ver}" | tee -a "${log}"

install_end=$(date +%s)
install_secs=$((install_end - install_start))
echo "Install took ${install_secs}s" | tee -a "${log}"
echo "" | tee -a "${log}"
echo "--- test output ---" | tee -a "${log}"

test_start=$(date +%s)
set +e
(cd "${work}" && timeout "${TIMEOUT_SECS}" bash -c "${test_cmd}") >>"${log}" 2>&1
rc=$?
set -e
test_end=$(date +%s)
test_secs=$((test_end - test_start))

echo "" | tee -a "${log}"
echo "exit_code=${rc}" | tee -a "${log}"
echo "test_runtime_secs=${test_secs}" | tee -a "${log}"

status="PASS"
if [[ "${rc}" -eq 124 ]]; then
    status="TIMEOUT"
elif [[ "${rc}" -ne 0 ]]; then
    status="FAIL"
fi

{
    echo "package=${name}"
    echo "status=${status}"
    echo "exit_code=${rc}"
    echo "tornado=${tornado_ver}"
    echo "install_secs=${install_secs}"
    echo "test_secs=${test_secs}"
} > "${result}"

deactivate || true
echo "Result: ${status}"
exit "${rc}"

#!/usr/bin/env bash
# Tests for the harness itself.
#
# The definition/report/diff tests are offline and always run. The run_one.sh
# status-mapping tests need to install tornado, so they are skipped with a
# message if that is not possible; CI always runs them.
#
#   tests/harness_test.sh
#
# Each test builds a throwaway repo root (a copy of scripts/ plus synthetic
# packages/) so nothing touches the real definitions and paths still resolve the
# way they do in a real checkout.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "${TMPROOT}"' EXIT

passed=0
failed=0
skipped=0

ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; passed=$((passed + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n     %s\n' "$1" "${2:-}"; failed=$((failed + 1)); }
skip() { printf '  \033[33mskip\033[0m %s (%s)\n' "$1" "$2"; skipped=$((skipped + 1)); }

# check <description> <expected> <actual>
check() {
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

# new_root -- a fresh fake repo root with the real scripts and an empty packages/
new_root() {
    local root
    root="$(mktemp -d -p "${TMPROOT}")"
    cp -r "${REPO}/scripts" "${root}/scripts"
    # The real build constraints come along, so these tests exercise the same
    # install path a real run takes rather than routing around it.
    cp "${REPO}/build-constraints.txt" "${root}/build-constraints.txt"
    mkdir -p "${root}/packages"
    echo "${root}"
}

# make_pkg <root> <name> <rank> <test-body> [extra package.env lines]
# Writes a synthetic package whose "checkout" is an installable stub.
make_pkg() {
    local root="$1" name="$2" rank="$3" body="$4" extra="${5:-}"
    local dir="${root}/packages/${name}"
    mkdir -p "${dir}"
    printf '%s==1.0.0\n' "${name}" > "${dir}/requirements.txt"
    {
        echo "rank=${rank}"
        echo "repo=https://example.invalid/${name}"
        echo "tag_template=v{version}"
        echo "subdir=."
        [[ -n "${extra}" ]] && echo "${extra}"
    } > "${dir}/package.env"
    printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "${body}" > "${dir}/test.sh"
    chmod +x "${dir}/test.sh"
    echo "# ${name}" > "${dir}/README.md"

    # A checkout that `uv pip install -e .` accepts with no dependencies.
    local checkout="${root}/checkouts/${name}"
    mkdir -p "${checkout}"
    cat > "${checkout}/pyproject.toml" <<EOF
[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"

[project]
name = "${name}-stub"
version = "1.0.0"
EOF
}

echo "== package definitions =="

root="$(new_root)"
make_pkg "${root}" alpha 1 'true'
make_pkg "${root}" beta 2 'true'
out="$(cd "${root}" && python3 scripts/validate_packages.py 2>&1)"
check "a well-formed pair of packages validates" "checked 2 package(s): OK" "${out}"

out="$(cd "${root}" && python3 scripts/pkglib.py matrix "" 2>&1)"
check "matrix is rank-ordered JSON" '["alpha", "beta"]' "${out}"

out="$(cd "${root}" && python3 scripts/pkglib.py resolve 2 2>&1)"
check "rank resolves to a name" "beta" "${out}"

out="$(cd "${root}" && python3 scripts/pkglib.py env alpha 2>&1 | grep '^PKG_REF=')"
check "ref is derived from tag_template + pin" "PKG_REF=v1.0.0" "${out}"

# Each of these must be rejected, because every one of them is a way for the
# harness to test something other than what it claims.
reject() {
    local desc="$1" mutate="$2"
    local r
    r="$(new_root)"
    make_pkg "${r}" alpha 1 'true'
    make_pkg "${r}" beta 2 'true'
    ( cd "${r}" && eval "${mutate}" )
    if (cd "${r}" && python3 scripts/validate_packages.py >/dev/null 2>&1); then
        bad "${desc}" "validate_packages.py accepted it"
    else
        ok "${desc}"
    fi
}
reject "duplicate rank is rejected"         "sed -i 's/^rank=2/rank=1/' packages/beta/package.env"
reject "missing required key is rejected"   "sed -i '/^subdir=/d' packages/beta/package.env"
reject "unknown key is rejected"            "echo 'tag_tempalte=v{version}' >> packages/beta/package.env"
reject "tag_template without {version} is rejected" \
                                            "sed -i 's|^tag_template=.*|tag_template=v1.0.0|' packages/beta/package.env"
reject "two requirements in one file is rejected" \
                                            "echo 'extra==1.0' >> packages/beta/requirements.txt"
reject "unpinned requirement is rejected"   "echo 'beta' > packages/beta/requirements.txt"
reject "non-executable test.sh is rejected" "chmod -x packages/beta/test.sh"
reject "missing README.md is rejected"      "rm packages/beta/README.md"

echo "== report.sh =="

fixtures="$(mktemp -d -p "${TMPROOT}")"
mkdir -p "${fixtures}/results" "${fixtures}/logs"
write_result() {
    printf 'package=%s\nstatus=%s\nexit_code=%s\ntornado=6.6.dev1\ntest_secs=1\n' \
        "$1" "$2" "$3" > "${fixtures}/results/$1.txt"
}

write_result onlygreen PASS 0
RESULTS_DIR="${fixtures}/results" LOGS_DIR="${fixtures}/logs" \
    "${REPO}/scripts/report.sh" >/dev/null 2>&1
check "all-green exits 0" "0" "$?"

for status in FAIL TIMEOUT INSTALL_FAIL SETUP_FAIL TORNADO_INSTALL_FAIL TORNADO_MISMATCH UNKNOWN; do
    write_result probe "${status}" 1
    RESULTS_DIR="${fixtures}/results" LOGS_DIR="${fixtures}/logs" \
        "${REPO}/scripts/report.sh" >/dev/null 2>&1
    check "${status} fails the gate" "1" "$?"
done

RESULTS_DIR="${fixtures}/results" LOGS_DIR="${fixtures}/logs" FAIL_ON_REGRESSION=0 \
    "${REPO}/scripts/report.sh" >/dev/null 2>&1
check "FAIL_ON_REGRESSION=0 reports without failing" "0" "$?"

out="$(RESULTS_DIR="${fixtures}/results" LOGS_DIR="${fixtures}/logs" \
    "${REPO}/scripts/report.sh" 2>&1 | grep -c '| probe |')"
check "every package appears in the table" "1" "${out}"

echo "== changed_packages.sh =="

root="$(new_root)"
make_pkg "${root}" alpha 1 'true'
make_pkg "${root}" beta 2 'true'
(
    cd "${root}" || exit 1
    git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm base
    echo 'alpha==1.0.1' > packages/alpha/requirements.txt
    git add -A && git -c user.email=t@t -c user.name=t commit -qm bump
) >/dev/null 2>&1
out="$(cd "${root}" && ./scripts/changed_packages.sh HEAD~1 2>&1)"
check "only the bumped package is reported" "alpha" "${out}"
out="$(cd "${root}" && ./scripts/changed_packages.sh HEAD 2>&1)"
check "no package change reports nothing" "" "${out}"

echo "== resolve_tornado_artifact.sh =="

art="$(mktemp -d -p "${TMPROOT}")"
touch "${art}/tornado-6.6.dev1-cp39-abi3-manylinux_2_17_x86_64.whl" "${art}/tornado-6.6.dev1.tar.gz"
out="$(cd "${REPO}" && ./scripts/resolve_tornado_artifact.sh "${art}" | grep '^TORNADO_EXPECT_VERSION=')"
check "version is read from the wheel name" "TORNADO_EXPECT_VERSION=6.6.dev1" "${out}"
out="$(cd "${REPO}" && ./scripts/resolve_tornado_artifact.sh "${art}" | grep -c '\.whl$')"
check "a wheel is preferred over the sdist" "1" "${out}"
empty="$(mktemp -d -p "${TMPROOT}")"
(cd "${REPO}" && ./scripts/resolve_tornado_artifact.sh "${empty}" >/dev/null 2>&1)
check "an artifact with no tornado build fails" "1" "$?"

echo "== run_one.sh status mapping =="

# These need to install tornado. Probe once rather than failing ten times.
probe="$(mktemp -d -p "${TMPROOT}")"
if ! (uv venv --python 3.11 "${probe}/v" >/dev/null 2>&1 \
        && VIRTUAL_ENV="${probe}/v" uv pip install -q tornado >/dev/null 2>&1); then
    skip "run_one.sh status mapping" "cannot install tornado (no network?)"
else
    # run_status <test-body> [env assignments...] -> "<status> <rc>"
    run_status() {
        local body="$1"; shift
        local r
        r="$(new_root)"
        make_pkg "${r}" subject 1 "${body}"
        ( cd "${r}" && env "$@" ./scripts/run_one.sh subject >/dev/null 2>&1 )
        local rc=$?
        local status
        status="$(awk -F= '/^status=/ {print $2}' "${r}/results/subject.txt" 2>/dev/null)"
        echo "${status:-NORESULT} ${rc}"
    }

    check "a passing suite is PASS/0" "PASS 0" \
        "$(run_status 'true' TORNADO_SPEC=tornado)"

    # The regression that made a red package invisible: common.sh enables
    # `set -e`, so an unguarded test invocation aborted run_one.sh before the
    # result file was written.
    check "a failing suite is FAIL/1 and still writes a result" "FAIL 1" \
        "$(run_status 'exit 1' TORNADO_SPEC=tornado)"

    check "an unusual exit code is preserved" "FAIL 7" \
        "$(run_status 'exit 7' TORNADO_SPEC=tornado)"

    check "a hanging suite is TIMEOUT/124" "TIMEOUT 124" \
        "$(run_status 'sleep 30' TORNADO_SPEC=tornado TIMEOUT_SECS=2 RETRY_TIMEOUT=0)"

    check "an uninstallable tornado is TORNADO_INSTALL_FAIL/5" "TORNADO_INSTALL_FAIL 5" \
        "$(run_status 'true' TORNADO_SPEC=tornado==0.0.0.nope)"

    check "a wrong tornado version is TORNADO_MISMATCH/6" "TORNADO_MISMATCH 6" \
        "$(run_status 'true' TORNADO_SPEC=tornado==6.5.10 TORNADO_EXPECT_VERSION=6.6.dev1)"

    # A suite that swaps tornado underneath itself invalidates its own result.
    check "tornado changing mid-run is TORNADO_MISMATCH/6" "TORNADO_MISMATCH 6" \
        "$(run_status 'uv pip install -q tornado==6.5.8' TORNADO_SPEC=tornado==6.5.10)"

    # A failing setup hook must not be reported as a test failure.
    r="$(new_root)"
    make_pkg "${r}" subject 1 'true'
    printf '#!/usr/bin/env bash\nexit 1\n' > "${r}/packages/subject/setup.sh"
    chmod +x "${r}/packages/subject/setup.sh"
    ( cd "${r}" && TORNADO_SPEC=tornado ./scripts/run_one.sh subject >/dev/null 2>&1 )
    rc=$?
    status="$(awk -F= '/^status=/ {print $2}' "${r}/results/subject.txt" 2>/dev/null)"
    check "a failing setup.sh is SETUP_FAIL/4" "SETUP_FAIL 4" "${status} ${rc}"

    # COV_ARGS is how the harness turns coverage off; a package's test.sh must
    # see it empty rather than falling back to its own default.
    # shellcheck disable=SC2016  # the test body is evaluated inside the package
    check "COVERAGE=0 exports COV_ARGS empty" "PASS 0" \
        "$(run_status '[[ -z "${COV_ARGS-unset}" ]]' TORNADO_SPEC=tornado COVERAGE=0)"
    # shellcheck disable=SC2016  # the test body is evaluated inside the package
    check "COVERAGE=1 leaves COV_ARGS to the package default" "PASS 0" \
        "$(run_status '[[ "${COV_ARGS-unset}" == "unset" ]]' TORNADO_SPEC=tornado COVERAGE=1)"

    # uv errors on a constraints file that is not there, so pointing at one
    # unconditionally turned every install into an INSTALL_FAIL. A checkout
    # without the file must still work.
    r="$(new_root)"
    rm -f "${r}/build-constraints.txt"
    make_pkg "${r}" subject 1 'true'
    ( cd "${r}" && TORNADO_SPEC=tornado ./scripts/run_one.sh subject >/dev/null 2>&1 )
    rc=$?
    status="$(awk -F= '/^status=/ {print $2}' "${r}/results/subject.txt" 2>/dev/null)"
    check "a missing build-constraints.txt is not fatal" "PASS 0" "${status} ${rc}"
fi

echo ""
printf '%d passed, %d failed, %d skipped\n' "${passed}" "${failed}" "${skipped}"
[[ "${failed}" -eq 0 ]]

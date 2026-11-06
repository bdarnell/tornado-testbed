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

# make_pkg <root> <name> <test-body> [extra package.env lines]
# Writes a synthetic package whose "checkout" is an installable stub.
make_pkg() {
    local root="$1" name="$2" body="$3" extra="${4:-}"
    local dir="${root}/packages/${name}"
    mkdir -p "${dir}"
    printf '%s==1.0.0\n' "${name}" > "${dir}/requirements.txt"
    {
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
# Created out of order, to show the order comes from the names.
make_pkg "${root}" beta 'true'
make_pkg "${root}" alpha 'true'
out="$(cd "${root}" && python3 scripts/validate_packages.py 2>&1)"
check "a well-formed pair of packages validates" "checked 2 package(s): OK" "${out}"

out="$(cd "${root}" && python3 scripts/pkglib.py matrix "" 2>&1)"
check "matrix is alphabetical JSON" '["alpha", "beta"]' "${out}"

out="$(cd "${root}" && python3 scripts/pkglib.py resolve beta 2>&1)"
check "a name resolves to itself" "beta" "${out}"

if (cd "${root}" && python3 scripts/pkglib.py resolve 2 >/dev/null 2>&1); then
    bad "a numeric selector is rejected" "resolve accepted '2'"
else
    ok "a numeric selector is rejected"
fi

out="$(cd "${root}" && python3 scripts/pkglib.py apt alpha 2>&1)"
check "no apt_packages means nothing to install" "" "${out}"

echo 'apt_packages=gifsicle libjpeg-turbo-progs' >> "${root}/packages/beta/package.env"
out="$(cd "${root}" && python3 scripts/pkglib.py apt beta 2>&1)"
check "apt_packages is reported for the workflow" "gifsicle libjpeg-turbo-progs" "${out}"

out="$(cd "${root}" && python3 scripts/pkglib.py env alpha 2>&1 | grep '^PKG_REF=')"
check "ref is derived from tag_template + pin" "PKG_REF=v1.0.0" "${out}"

printf 'install_method=pypi\noptional_dependency_group=tests\n' >> "${root}/packages/beta/package.env"
out="$(cd "${root}" && python3 scripts/pkglib.py env beta 2>&1 | grep '^PKG_OPTIONAL_DEPENDENCY_GROUP=')"
check "optional_dependency_group is exported" "PKG_OPTIONAL_DEPENDENCY_GROUP=tests" "${out}"

# Each of these must be rejected, because every one of them is a way for the
# harness to test something other than what it claims.
reject() {
    local desc="$1" mutate="$2"
    local r
    r="$(new_root)"
    make_pkg "${r}" alpha 'true'
    make_pkg "${r}" beta 'true'
    ( cd "${r}" && eval "${mutate}" )
    if (cd "${r}" && python3 scripts/validate_packages.py >/dev/null 2>&1); then
        bad "${desc}" "validate_packages.py accepted it"
    else
        ok "${desc}"
    fi
}
reject "a leftover rank key is rejected"    "echo 'rank=1' >> packages/beta/package.env"
reject "missing required key is rejected"   "sed -i '/^subdir=/d' packages/beta/package.env"
reject "unknown key is rejected"            "echo 'tag_tempalte=v{version}' >> packages/beta/package.env"
reject "tag_template without {version} is rejected" \
                                            "sed -i 's|^tag_template=.*|tag_template=v1.0.0|' packages/beta/package.env"
reject "two requirements in one file is rejected" \
                                            "echo 'extra==1.0' >> packages/beta/requirements.txt"
reject "unpinned requirement is rejected"   "echo 'beta' > packages/beta/requirements.txt"
reject "optional_dependency_group without install_method=pypi is rejected" \
                                            "echo 'optional_dependency_group=tests' >> packages/beta/package.env"
reject "optional_dependency_group naming two extras is rejected" \
                                            "printf 'install_method=pypi\noptional_dependency_group=tests,docs\n' >> packages/beta/package.env"
reject "non-executable test.sh is rejected" "chmod -x packages/beta/test.sh"
reject "missing README.md is rejected"      "rm packages/beta/README.md"
reject "non-integer min_coverage is rejected" \
                                            "echo 'min_coverage=lots' >> packages/beta/package.env"
reject "out-of-range min_coverage is rejected" \
                                            "echo 'min_coverage=101' >> packages/beta/package.env"
reject "a --cov flag outside COV_ARGS is rejected" \
                                            "echo 'python -m pytest --cov-config=/dev/null' >> packages/beta/test.sh"

# dependabot.yml must list each package directory explicitly: a missing entry
# means a pin nobody bumps, and a "/packages/*" glob opens every bump twice.
dependabot() {
    mkdir -p .github
    printf 'version: 2\nupdates:\n  - package-ecosystem: "pip"\n    directories:\n' > .github/dependabot.yml
    local d
    for d in "$@"; do printf '      - "%s"\n' "${d}" >> .github/dependabot.yml; done
}
r="$(new_root)"
make_pkg "${r}" alpha 'true'
make_pkg "${r}" beta 'true'
out="$(cd "${r}" && dependabot /packages/alpha /packages/beta && python3 scripts/validate_packages.py 2>&1)"
check "a dependabot.yml listing every package validates" "checked 2 package(s): OK" "${out}"
reject "a package missing from dependabot.yml is rejected" "dependabot /packages/alpha"
reject "a dependabot.yml entry with no package is rejected" \
                                            "dependabot /packages/alpha /packages/beta /packages/gamma"
reject "a dependabot.yml glob is rejected"  "dependabot '/packages/*'"

echo "== constraints.lock =="

# lock <root> <name> <pin> <python> [requirement...] -- write a lock by hand.
lock() {
    local root="$1" name="$2" pin="$3" py="$4"; shift 4
    { echo "# pin: ${pin}"; echo "# python: ${py}"; printf '%s\n' "$@"; } \
        > "${root}/packages/${name}/constraints.lock"
}
r="$(new_root)"
make_pkg "${r}" alpha 'true'
out="$(cd "${r}" && python3 scripts/pkglib.py lock-status alpha 3.13 2>&1)"
check "no lock is missing" "missing: no constraints.lock" "${out}"
lock "${r}" alpha alpha==1.0.0 3.13 six==1.16.0
out="$(cd "${r}" && python3 scripts/pkglib.py lock-status alpha 3.13 2>&1)"
check "a lock for this pin and python is current" "current" "${out}"
out="$(cd "${r}" && python3 scripts/pkglib.py lock-status alpha 3.12 2>&1)"
check "a lock for another python is stale" \
    "stale: generated for python 3.13, running 3.12" "${out}"
lock "${r}" alpha alpha==0.9.0 3.13 six==1.16.0
out="$(cd "${r}" && python3 scripts/pkglib.py lock-status alpha 3.13 2>&1)"
check "a lock for another pin is stale" \
    "stale: generated for alpha==0.9.0, pin is now alpha==1.0.0" "${out}"

# The freeze filter: tornado is force-installed and the package's version is
# its pin, so neither may be locked; editables and URLs cannot be constraints.
out="$(cd "${r}" && printf '%s\n' 'Six==1.16.0' 'tornado==6.5' 'alpha==1.0.0' \
        '-e file:///x' 'foo @ git+https://example.invalid/foo' 'Zope.Interface==7.0' \
    | python3 scripts/pkglib.py write-lock alpha 3.13 \
    && grep -v '^#' packages/alpha/constraints.lock | tr '\n' ' ')"
check "write-lock keeps only index pins other than tornado and the package" \
    "six==1.16.0 zope-interface==7.0 " "${out}"
out="$(cd "${r}" && python3 scripts/pkglib.py lock-status alpha 3.13 2>&1)"
check "a freshly written lock is current" "current" "${out}"

reject "a lock that constrains tornado is rejected" \
    "printf '# pin: beta==1.0.0\n# python: 3.13\ntornado==6.5\n' > packages/beta/constraints.lock"
reject "a lock that constrains its own package is rejected" \
    "printf '# pin: beta==1.0.0\n# python: 3.13\nbeta==1.0.0\n' > packages/beta/constraints.lock"
reject "a lock with an unpinned line is rejected" \
    "printf '# pin: beta==1.0.0\n# python: 3.13\nsix\n' > packages/beta/constraints.lock"
reject "a lock without its header is rejected" \
    "printf 'six==1.16.0\n' > packages/beta/constraints.lock"

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

# An unlocked run is called out but does not change the verdict.
unl="$(mktemp -d -p "${TMPROOT}")"
mkdir -p "${unl}/results" "${unl}/logs"
printf 'package=loose\nstatus=PASS\nexit_code=0\nlock=unlocked\n' > "${unl}/results/loose.txt"
printf 'package=tight\nstatus=PASS\nexit_code=0\nlock=locked\n' > "${unl}/results/tight.txt"
out="$(RESULTS_DIR="${unl}/results" LOGS_DIR="${unl}/logs" "${REPO}/scripts/report.sh" 2>&1)"
check "an unlocked package still passes the gate" "0" "$?"
# shellcheck disable=SC2016  # literal backticks
check "an unlocked package is named in the report" "1" \
    "$(grep -c 'Ran without a current lock.*`loose`' <<<"${out}")"
# shellcheck disable=SC2016  # literal backticks
check "a locked package is not" "0" "$(grep -c 'lock.*`tight`' <<<"${out}")"

echo "== changed_packages.sh =="

root="$(new_root)"
make_pkg "${root}" alpha 'true'
make_pkg "${root}" beta 'true'
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
    # run_status <test-body> [VAR=value...] -> "<status> <rc>"
    # EXTRA_ENV=<line> is pulled out and appended to the package's package.env
    # rather than passed to run_one.sh.
    run_status() {
        local body="$1"; shift
        local extra="" arg
        local -a envs=()
        for arg in "$@"; do
            case "${arg}" in
                EXTRA_ENV=*) extra="${arg#EXTRA_ENV=}" ;;
                *) envs+=("${arg}") ;;
            esac
        done
        local r
        r="$(new_root)"
        make_pkg "${r}" subject "${body}" "${extra}"
        ( cd "${r}" && env "${envs[@]}" ./scripts/run_one.sh subject >/dev/null 2>&1 )
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
    make_pkg "${r}" subject 'true'
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

    # The coverage floor. A synthetic package covers a sliver of tornado, which
    # is enough to exercise the numeric comparison in both directions.
    # Importing tornado.web covers ~14% of tornado, which is enough headroom to
    # sit clearly above a small floor and clearly below a large one.
    # shellcheck disable=SC2016  # COVERAGE_FILE is expanded inside the package
    cover_body='python -m coverage run --data-file="${COVERAGE_FILE}" --source=tornado -m tornado.web'

    # shellcheck disable=SC2016  # the body is evaluated inside the package
    check "coverage above the floor passes" "PASS 0" \
        "$(run_status "${cover_body}" TORNADO_SPEC=tornado COVERAGE=1 \
            EXTRA_ENV=min_coverage=5)"

    # shellcheck disable=SC2016
    check "coverage below the floor is COVERAGE_LOW/7" "COVERAGE_LOW 7" \
        "$(run_status "${cover_body}" TORNADO_SPEC=tornado COVERAGE=1 \
            EXTRA_ENV=min_coverage=99)"

    # A floor with nothing measured is a broken test command, not a pass.
    check "a floor with no coverage data is COVERAGE_LOW/7" "COVERAGE_LOW 7" \
        "$(run_status 'true' TORNADO_SPEC=tornado COVERAGE=1 EXTRA_ENV=min_coverage=10)"

    # Regression: the release gate runs with COVERAGE=0, and briefly every
    # package with a floor failed there because the check ran anyway.
    check "COVERAGE=0 does not check the floor" "PASS 0" \
        "$(run_status 'true' TORNADO_SPEC=tornado COVERAGE=0 EXTRA_ENV=min_coverage=99)"

    check "no floor declared means no check" "PASS 0" \
        "$(run_status 'true' TORNADO_SPEC=tornado COVERAGE=1)"

    # Locks. The stub package depends on nothing, so the test body installs a
    # real distribution and checks which version it got: WANT=1.16.0 means
    # exactly that, WANT=!1.16.0 means anything newer (whatever six is now).
    # shellcheck disable=SC2016  # evaluated inside the package
    six_body='uv pip install -q six && python -c "import six, sys, os; w = os.environ[\"WANT\"]; sys.exit((six.__version__ == w.lstrip(\"!\")) == w.startswith(\"!\"))"'
    # run_one.sh builds its venvs with PYTHON_VERSION, 3.13 unless overridden.
    py_minor="${PYTHON_VERSION:-3.13}"

    r="$(new_root)"
    make_pkg "${r}" subject "${six_body}"
    lock "${r}" subject subject==1.0.0 "${py_minor}" six==1.16.0
    ( cd "${r}" && TORNADO_SPEC=tornado WANT=1.16.0 ./scripts/run_one.sh subject >/dev/null 2>&1 )
    rc=$?
    check "a current lock holds what test.sh installs" "PASS 0 lock=locked" \
        "$(awk -F= '/^status=/ {print $2}' "${r}/results/subject.txt") ${rc} $(grep '^lock=' "${r}/results/subject.txt")"

    r="$(new_root)"
    make_pkg "${r}" subject "${six_body}"
    lock "${r}" subject subject==0.9.0 "${py_minor}" six==1.16.0
    ( cd "${r}" && TORNADO_SPEC=tornado WANT=!1.16.0 ./scripts/run_one.sh subject >/dev/null 2>&1 )
    rc=$?
    check "a stale lock is not applied, and the run says so" "PASS 0 lock=unlocked" \
        "$(awk -F= '/^status=/ {print $2}' "${r}/results/subject.txt") ${rc} $(grep '^lock=' "${r}/results/subject.txt")"

    # A refresh ignores the old lock, still reports the real test result, and
    # leaves a current lock behind -- even when the suite fails.
    r="$(new_root)"
    make_pkg "${r}" subject "${six_body}; exit 3"
    lock "${r}" subject subject==1.0.0 "${py_minor}" six==1.16.0
    ( cd "${r}" && LOCK_MODE=refresh TORNADO_SPEC=tornado WANT=!1.16.0 \
        ./scripts/run_one.sh subject >/dev/null 2>&1 )
    rc=$?
    check "a refresh reports the suite's own result" "FAIL 3 lock=refreshed" \
        "$(awk -F= '/^status=/ {print $2}' "${r}/results/subject.txt") ${rc} $(grep '^lock=' "${r}/results/subject.txt")"
    check "a refresh writes the tested environment" "1 0" \
        "$(grep -c '^six==' "${r}/packages/subject/constraints.lock") $(grep -c '^six==1.16.0$' "${r}/packages/subject/constraints.lock")"
    check "a refreshed lock is current" "current" \
        "$(cd "${r}" && python3 scripts/pkglib.py lock-status subject "${py_minor}")"
    check "a refreshed lock leaves tornado alone" "0" \
        "$(grep -c '^tornado==' "${r}/packages/subject/constraints.lock")"

    # uv errors on a constraints file that is not there, so pointing at one
    # unconditionally turned every install into an INSTALL_FAIL. A checkout
    # without the file must still work.
    r="$(new_root)"
    rm -f "${r}/build-constraints.txt"
    make_pkg "${r}" subject 'true'
    ( cd "${r}" && TORNADO_SPEC=tornado ./scripts/run_one.sh subject >/dev/null 2>&1 )
    rc=$?
    status="$(awk -F= '/^status=/ {print $2}' "${r}/results/subject.txt" 2>/dev/null)"
    check "a missing build-constraints.txt is not fatal" "PASS 0" "${status} ${rc}"
fi

echo ""
printf '%d passed, %d failed, %d skipped\n' "${passed}" "${failed}" "${skipped}"
[[ "${failed}" -eq 0 ]]

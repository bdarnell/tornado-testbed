#!/usr/bin/env bash
# Turn results/<name>.txt into a report, and decide the exit code.
#
# Shared by both ways the testbed runs: scripts/ci.sh (serial, one machine) and
# the per-package job matrix in .github/workflows/testbed.yml, which downloads
# each job's result files and then calls this. Keeping one implementation means
# the two paths cannot disagree about whether a run passed.
#
# Writes a markdown summary to stdout and to $GITHUB_STEP_SUMMARY, exposes
# total/passed/failed via $GITHUB_OUTPUT, and echoes the tail of each failing
# package's log so a traceback is readable in the web UI without downloading
# the artifact.
#
# Inputs (environment):
#   TORNADO_SPEC        What was tested, for the report header.
#   FAIL_ON_REGRESSION  "1" (default) exits non-zero unless every package
#                       passed. "0" reports only.
#   LOG_TAIL            Lines of each failing log to echo (default 200).
set -uo pipefail
source "$(dirname "$0")/common.sh"

TORNADO_SPEC="${TORNADO_SPEC:-tornado}"
FAIL_ON_REGRESSION="${FAIL_ON_REGRESSION:-1}"
LOG_TAIL="${LOG_TAIL:-200}"

group()    { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::group::$*" || echo "=== $* ==="; }
endgroup() { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::endgroup::" || true; }

# ── Render the summary ───────────────────────────────────────────────────────
summary_md="$(python3 - "$RESULTS_DIR" "$TORNADO_SPEC" <<'PY'
import os, sys, glob

results_dir, tornado_spec = sys.argv[1], sys.argv[2]
rows, counts = [], {}
for path in sorted(glob.glob(os.path.join(results_dir, "*.txt"))):
    if os.path.basename(path) == "summary.txt":
        continue
    kv = {}
    with open(path) as f:
        for line in f:
            if "=" in line:
                k, _, v = line.strip().partition("=")
                kv[k] = v
    name = kv.get("package") or os.path.splitext(os.path.basename(path))[0]
    status = kv.get("status", "UNKNOWN")
    counts[status] = counts.get(status, 0) + 1
    rows.append((name, status, kv.get("exit_code", "?"),
                 kv.get("tornado", "?"), kv.get("test_secs", "?")))

emoji = {"PASS": "✅", "FAIL": "❌", "TIMEOUT": "⏱️",
         "INSTALL_FAIL": "🛠️", "SETUP_FAIL": "🛠️",
         "TORNADO_INSTALL_FAIL": "🌪️", "TORNADO_MISMATCH": "🌪️"}

out = []
out.append("## Tornado testbed results")
out.append("")
out.append(f"**Tornado under test:** `{tornado_spec}`")
out.append("")
total = sum(counts.values())
order = ["PASS", "FAIL", "TIMEOUT", "INSTALL_FAIL", "SETUP_FAIL",
         "TORNADO_INSTALL_FAIL", "TORNADO_MISMATCH", "UNKNOWN"]
badge = " · ".join(f"{emoji.get(s, '•')} {s}: {counts[s]}"
                   for s in order if s in counts)
out.append(f"{total} package(s) — {badge}")
out.append("")
out.append("| Package | Status | RC | Tornado | Time (s) |")
out.append("|---------|--------|----|---------|----------|")
for name, status, rc, tornado, secs in rows:
    out.append(f"| {name} | {emoji.get(status, '')} {status} | {rc} | {tornado} | {secs} |")
print("\n".join(out))

gh_out = os.environ.get("GITHUB_OUTPUT")
if gh_out:
    passed = counts.get("PASS", 0)
    failed = total - passed
    with open(gh_out, "a") as f:
        f.write(f"total={total}\n")
        f.write(f"passed={passed}\n")
        f.write(f"failed={failed}\n")
PY
)"

echo ""
echo "${summary_md}"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "${summary_md}" >> "${GITHUB_STEP_SUMMARY}"
fi

# ── Surface failing-package logs inline ──────────────────────────────────────
not_passed=0
for res in "${RESULTS_DIR}"/*.txt; do
    [[ -e "${res}" ]] || continue
    [[ "$(basename "${res}")" == "summary.txt" ]] && continue
    status="$(awk -F= '/^status=/ {print $2}' "${res}")"
    [[ "${status}" == "PASS" ]] && continue
    not_passed=$((not_passed + 1))

    name="$(awk -F= '/^package=/ {print $2}' "${res}")"
    name="${name:-$(basename "${res}" .txt)}"
    log="${LOGS_DIR}/${name}.log"
    [[ -f "${log}" ]] || continue

    group "FAILED ${name} (${status}) — last ${LOG_TAIL} lines of ${name}.log"
    tail -n "${LOG_TAIL}" "${log}"
    endgroup

    # Pytest's "short test summary info" block is the most useful one-glance
    # digest; fall back to the log tail if the run never reached that point.
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        digest="$(sed 's/\x1b\[[0-9;]*m//g' "${log}" \
                  | grep -E '^(FAILED|ERROR) |[0-9]+ (failed|passed|error)' \
                  | head -n 60)"
        [[ -z "${digest}" ]] && digest="$(tail -n "${LOG_TAIL}" "${log}" \
                  | sed 's/\x1b\[[0-9;]*m//g')"
        {
            echo ""
            echo "<details><summary>❌ ${name} (${status}) — failure detail</summary>"
            echo ""
            echo '```'
            echo "${digest}"
            echo '```'
            echo ""
            echo "</details>"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
done

# ── Exit code ────────────────────────────────────────────────────────────────
# The report is fully written by this point, so failing here still leaves
# everything a human needs behind.
#
# The harness curates a green baseline: known-bad downstream tests are
# deselected in each package's test.sh with the reason recorded next to them. So
# anything other than PASS is a regression to look at, and the gate says so.
if [[ "${not_passed}" -gt 0 ]]; then
    echo ""
    echo "${not_passed} package(s) did not pass against ${TORNADO_SPEC}."
    if [[ "${FAIL_ON_REGRESSION}" == "1" ]]; then
        exit 1
    fi
    echo "FAIL_ON_REGRESSION=0, reporting only."
fi
exit 0

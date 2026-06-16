#!/usr/bin/env bash
# Run the full testbed in a CI environment (e.g. GitHub Actions).
#
# This is the single entry point both workflows (this repo's own test action
# and the workflow_dispatch action that lives in the tornado repo) call, so the
# YAML stays thin and all the logic lives here in version-controlled scripts.
#
# Unlike a local run it never writes anything back into git history: results are
# surfaced via stdout, the GitHub step summary ($GITHUB_STEP_SUMMARY), and the
# files left in logs/ results/ coverage_html/ for the workflow to upload as
# build artifacts.
#
# Inputs (environment):
#   TORNADO_SPEC  What to test against. Anything `uv pip install` accepts:
#                   - a release pin        "tornado==6.5.1"
#                   - a local checkout      "/path/to/tornado"
#                   - a built wheel         "/path/to/tornado-7.0-py3-none-any.whl"
#                   - a branch/tag/SHA      "git+https://github.com/tornadoweb/tornado.git@BRANCH"
#                 Defaults to "tornado" (latest PyPI release).
#   ONLY          Optional space-separated list of package names/indices to run
#                 instead of the whole manifest (handy for debugging the action).
set -uo pipefail
source "$(dirname "$0")/common.sh"

export TORNADO_SPEC="${TORNADO_SPEC:-tornado}"

# GitHub Actions log-group helpers that degrade to no-ops outside Actions.
group()    { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::group::$*" || echo "=== $* ==="; }
endgroup() { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::endgroup::" || true; }

echo "Testing downstream packages against TORNADO_SPEC=${TORNADO_SPEC}"

group "setup: clone downstream packages"
bash "${ROOT_DIR}/scripts/setup.sh"
endgroup

if [[ -n "${ONLY:-}" ]]; then
    for sel in ${ONLY}; do
        group "run: ${sel}"
        bash "${ROOT_DIR}/scripts/run_one.sh" "${sel}" || true
        endgroup
    done
    bash "${ROOT_DIR}/scripts/summarize.sh"
else
    group "run: all packages"
    bash "${ROOT_DIR}/scripts/run_all.sh"
    endgroup
fi

# Coverage reports are best-effort: a failed report build must not mask the
# actual test results that the run already produced.
group "coverage: build HTML reports"
bash "${ROOT_DIR}/scripts/gen_reports.sh" || echo "WARNING: coverage report generation failed"
endgroup

# ── Surface the results ──────────────────────────────────────────────────────
# Render a markdown summary (counts + per-package table) to stdout and, when
# running under Actions, to the job summary. Also expose machine-readable
# pass/fail counts via $GITHUB_OUTPUT.
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
         "INSTALL_FAIL": "🛠️", "SETUP_FAIL": "🛠️"}

out = []
out.append(f"## Tornado testbed results")
out.append("")
out.append(f"**Tornado under test:** `{tornado_spec}`")
out.append("")
total = sum(counts.values())
order = ["PASS", "FAIL", "TIMEOUT", "INSTALL_FAIL", "SETUP_FAIL", "UNKNOWN"]
badge = " · ".join(f"{emoji.get(s, '•')} {s}: {counts[s]}"
                   for s in order if s in counts)
out.append(f"{total} package(s) — {badge}")
out.append("")
out.append("| Package | Status | RC | Tornado | Time (s) |")
out.append("|---------|--------|----|---------|----------|")
for name, status, rc, tornado, secs in rows:
    out.append(f"| {name} | {emoji.get(status, '')} {status} | {rc} | {tornado} | {secs} |")
print("\n".join(out))

# Expose counts for the workflow.
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

# ci.sh itself always exits 0: a downstream test failure is data we want to
# report (and still upload artifacts for), not an infrastructure error. The
# workflow can inspect the `failed` output to decide whether to flag the run.
exit 0

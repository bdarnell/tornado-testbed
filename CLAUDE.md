# Working in this repo

A harness that runs the test suites of the most popular Tornado dependents
against a chosen Tornado build. It is called from tornado's own release build as
a reusable workflow, so it is release infrastructure: correctness of the
*signal* matters more than convenience.

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first — especially "the one rule".
[`REPORT.md`](REPORT.md) describes the current state, including the standing
limitations and the gotchas list, which is where most of the hard-won knowledge
lives.

## Orientation

- `packages/<name>/` — committed package definitions (pin, `package.env`,
  `test.sh`, optional `setup.sh`, `README.md`). See `packages/README.md`.
- `scripts/pkglib.py` — the only parser for those definitions; bash reads them
  through it via `scripts/common.sh`.
- `scripts/run_one.sh` — the important one. Builds a fresh venv, installs the
  package, force-installs the Tornado under test, runs `test.sh`, then verifies
  the Tornado did not change underneath it.
- `scripts/report.sh` — renders the summary and decides the exit code. Shared by
  the serial path (`ci.sh`) and the job matrix, so they cannot disagree.
- `checkouts/`, `logs/`, `results/`, `coverage/`, `coverage_html/` — all
  generated, none committed.

## Things that will bite you

- **`common.sh` enables `set -e`.** Guard anything whose failure you handle
  (`run_tests || rc=$?`). An unguarded failure aborts the script before the
  result file is written, so the package vanishes from the report instead of
  showing up red. This has happened.
- **Never edit a script while a run is using it.** Bash reads scripts
  incrementally; editing `ci.sh` mid-run corrupts execution.
- **`uv venv` has no `pip`.** Test commands that shell out must use `uv pip`.
- **Don't add a second source of truth for a version.** The pin in
  `requirements.txt` is it; the git tag is derived via `tag_template`. Two
  places to edit means two places to disagree.
- Statuses are load-bearing: `TORNADO_INSTALL_FAIL` and `TORNADO_MISMATCH`
  exist because a run that silently tested the wrong Tornado used to report
  `PASS`, and `COVERAGE_LOW` exists because a test command that stopped
  exercising Tornado also reports `PASS`. Keep them distinct from `FAIL`.
- **The coverage floor only applies when `COVERAGE=1`.** The release gate runs
  with coverage off, so checking the floor there would fail every package that
  declares one. It is also skipped unless the suite passed, so a real failure is
  never reported as `COVERAGE_LOW`.

The rest of the operational gotchas — `filterwarnings=error` in the Jupyter
stack, `relative_files=true` breaking standalone coverage reports, ZeroMQ
deadlocks that ignore SIGTERM, orphaned pytest processes, dependency drift — are
in `REPORT.md` under "Gotchas worth knowing".

## Verifying a change

```bash
python3 scripts/validate_packages.py
tests/harness_test.sh
shellcheck scripts/*.sh packages/*/*.sh
```

To check that the gate still catches a real Tornado regression, replay
tornado#3724 — but note it does **not** work at the current pin: jupyter_server
2.21.1 passes on 6.5.9. The replay needs the package temporarily pinned back to
2.14.2, and `packages/jupyter_server/README.md` has the exact procedure. Running
it against the current pin and seeing green proves nothing.

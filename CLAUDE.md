# Working in this repo

A harness that runs the test suites of the ten most popular Tornado dependents
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
  `PASS`. Keep them distinct from `FAIL`.

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

The end-to-end check that the gate still works is the tornado#3724 replay:
`jupyter_server` must fail on `tornado==6.5.9` and pass on `6.5.10`. See
`packages/jupyter_server/README.md`.

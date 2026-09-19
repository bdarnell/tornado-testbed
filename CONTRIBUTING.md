# Contributing to tornado-testbed

This repo exists to answer one question: **does a candidate Tornado break real
downstream consumers?** Every rule below follows from that.

## The one rule

**A red package must mean a Tornado regression.**

A test that fails for any other reason — downstream's own flakiness, dependency
drift, a missing system tool — gets deselected in that package's `test.sh` with
the reason written next to it. A package that is permanently red hides the
regressions the testbed exists to find, which is worse than not running it.

The corollary: never make a run green by loosening what it checks. If a genuine
Tornado failure is inconvenient, that is the testbed working.

## Layout

Package definitions live in `packages/<name>/` — one directory per downstream
package, holding its pin, metadata, test script and notes. See
[`packages/README.md`](packages/README.md). The harness itself is in `scripts/`.

Downstream sources are cloned into `checkouts/` and are not tracked. Nothing
generated is committed: no coverage reports, no result snapshots.

## Before you push

```bash
python3 scripts/validate_packages.py   # definitions are well-formed
tests/harness_test.sh                  # harness behaviour, offline
shellcheck scripts/*.sh packages/*/*.sh
```

Then run whatever you touched:

```bash
./scripts/setup.sh flower && ./scripts/run_one.sh flower
```

## Changing a package

Everything is in its directory. The version in `requirements.txt` is the only
place a version appears — the git tag is derived from it — and dependabot owns
it, so do not bump pins by hand unless you are fixing something dependabot
cannot.

When you add a deselect, put the reason on the line above it. That comment is
the most valuable text in this repo: it is what lets the next person tell a
Tornado regression from downstream noise.

## Changing the harness

The gate's credibility rests on `run_one.sh` failing loudly rather than falling
back. Any path where the requested Tornado is not what gets tested must be a
hard failure with its own status, not a warning. If you add one, add a case to
`tests/harness_test.sh` covering it.

`COVERAGE_LOW` is load-bearing in the same way `TORNADO_MISMATCH` is. It exists
because a test command that has stopped exercising Tornado still exits 0, and
nothing else the harness records would notice. Do not soften it into a warning,
and do not lower a package's `min_coverage` to get a run green — that is the
failure reporting itself correctly.

Note that `scripts/common.sh` enables `set -e`, so any command whose non-zero
exit you intend to handle needs guarding (`cmd || rc=$?`). An unguarded failure
aborts before the result file is written, which makes a red package invisible to
the gate.

## Releases

There is nothing to release. Tornado's own release build calls
`.github/workflows/testbed.yml` as a reusable workflow, so `main` is what runs.
Keep it green.

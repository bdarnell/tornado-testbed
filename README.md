# tornado-testbed

A reproducible harness for running the test suites of the most popular
open-source Python packages that depend on [Tornado](https://github.com/tornadoweb/tornado).
The goal is to give Tornado maintainers a way to sanity-check a candidate
release against real downstream consumers.

## Layout

```
packages.json          # manifest: top 10 dependents, pinned refs, test commands
scripts/
  common.sh            # shared helpers (reads packages.json)
  setup.sh             # clone each package at its pinned ref
  run_one.sh           # build an isolated uv venv and run one package's tests
  run_all.sh           # iterate run_one.sh over every package, summarise
  summarize.sh         # rebuild results/summary.txt from results/<name>.txt
  gen_reports.sh       # rebuild coverage_html/ from coverage/<name>.coverage
packages/              # populated by setup.sh (one git checkout per package)
logs/<name>.log        # full stdout+stderr for each package run
results/<name>.txt     # key=value summary for each package run
results/summary.txt    # overall table
coverage_html/         # committed HTML coverage reports (per package + merged)
REPORT.md              # current state of the harness
notes/                 # dated per-session history (see notes/README.md)
```

## Prerequisites

- `uv` (for per-package isolated Python 3.11 venvs)
- `git`
- POSIX shell + `python3` (used to parse the JSON manifest)

Docker is not required; each package is isolated via its own `uv` venv.
The manifest is the only place you need to edit to add/remove a package
or change its pinned ref or test command.

## Usage

```bash
# 1. Clone every dependent package at its pinned ref
./scripts/setup.sh

# 2a. Run everything
./scripts/run_all.sh

# 2b. Or run a single package, by name or index
./scripts/run_one.sh flower
./scripts/run_one.sh 6

# Test against a specific Tornado build/wheel:
TORNADO_SPEC="tornado==6.5.1" ./scripts/run_one.sh flower
TORNADO_SPEC="/path/to/tornado-7.0.0.dev0-py3-none-any.whl" ./scripts/run_all.sh
```

`TORNADO_SPEC` accepts anything `uv pip install` does (a version pin, a local
wheel, a VCS URL, etc.), so pointing the harness at a pre-release build is
one env var away.

## Running in CI / GitHub Actions

`scripts/ci.sh` is the single entry point for automated runs. It chains
`setup.sh` → `run_all.sh` → `gen_reports.sh`, then prints a markdown summary to
stdout and `$GITHUB_STEP_SUMMARY` and exposes `total`/`passed`/`failed` via
`$GITHUB_OUTPUT`. Unlike a local run it commits nothing — results are meant to
be read from the build log and downloaded from the uploaded `logs/`,
`results/`, and `coverage_html/` artifacts.

```bash
TORNADO_SPEC="git+https://github.com/tornadoweb/tornado.git@my-branch" ./scripts/ci.sh
ONLY="flower bokeh" ./scripts/ci.sh   # restrict to specific packages
```

Two thin workflows drive it:

- `.github/workflows/testbed.yml` — this repo's self-test. Run it from the
  Actions tab with a `tornado_ref` input to test against any Tornado
  branch/tag/SHA.
- `ci/tornado-downstream-testbed.yml` — a `workflow_dispatch` action meant to
  live in the **tornado** repo; it runs this harness against the tornado branch
  selected for the run. See `ci/README.md` for how to install it.

## Selection criteria

The ten packages were picked to maximise ecosystem coverage: popular (by
GitHub stars / PyPI downloads) AND declaring `tornado` directly in their
install requirements. See `packages.json` for the full list plus the
rationale and test command for each.

## Skipping policy

The task description permits skipping packages whose test suite is
exceptionally hard to run. For each such package we shrink `test_cmd` in
`packages.json` to a focused module or two that exercises the Tornado
integration points without pulling in a JS toolchain, Selenium, Playwright,
a database, or other heavyweight fixtures. The comment in each manifest
entry records which tests were dropped and why.

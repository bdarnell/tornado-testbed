# tornado-testbed

A reproducible harness for running the test suites of the most popular
open-source Python packages that depend on [Tornado](https://github.com/tornadoweb/tornado).
It gives Tornado maintainers a way to check a candidate release against real
downstream consumers before shipping it.

## Layout

```
packages/<name>/       package definitions: pin, metadata, test script, notes
                       (see packages/README.md)
scripts/
  pkglib.py            reads and validates the packages/ definitions
  common.sh            shared paths and helpers
  setup.sh             clone downstream sources at their pinned refs
  run_one.sh           build an isolated uv venv and run one package's tests
  run_all.sh           iterate run_one.sh over every package, summarise
  summarize.sh         rebuild results/summary.txt from results/<name>.txt
  gen_reports.sh       build coverage_html/ from coverage/<name>.coverage
  ci.sh                single entry point for automated runs
checkouts/<name>/      cloned downstream sources (generated)
logs/<name>.log        full stdout+stderr for each package run
results/<name>.txt     key=value summary for each package run
coverage_html/         coverage reports, built on demand
REPORT.md              current state of the harness
```

## Prerequisites

- `uv` (for per-package isolated venvs)
- `git`, and a POSIX shell with `python3`
- `node`/`npm` on PATH — jupyterhub's live-server tests need
  `configurable-http-proxy`
- `gifsicle` and `jpegtran` on PATH — thumbor's image pipeline shells out to
  them (Debian/Ubuntu: `apt-get install gifsicle libjpeg-turbo-progs`; CI
  installs them from thumbor's `apt_packages`)

Docker is not required; each package is isolated in its own `uv` venv.

## Usage

```bash
# Clone the downstream sources (all, or just some)
./scripts/setup.sh
./scripts/setup.sh flower bokeh

# Run everything, or one package by name
./scripts/run_all.sh
./scripts/run_one.sh flower

# Test against a specific Tornado build
TORNADO_SPEC="tornado==6.5.1"                      ./scripts/run_one.sh flower
TORNADO_SPEC="/path/to/tornado-7.0.0-py3-none-any.whl" ./scripts/run_all.sh
```

`TORNADO_SPEC` accepts anything `uv pip install` does — a version pin, a local
wheel, a VCS URL — so pointing the harness at a pre-release build is one env var
away. It is force-installed after the downstream package, and the run **fails**
rather than falling back if it cannot be installed or if anything later changes
the Tornado in the environment: a green run has to mean the requested Tornado
passed.

Other knobs: `TIMEOUT_SECS` (default 900, per package), `PYTHON_VERSION`
(default 3.11), `COVERAGE=0` to skip coverage measurement, `RETRY_TIMEOUT=0` to
disable the single retry on timeout.

## Running in CI

`scripts/ci.sh` is the entry point for automated runs. It chains
`setup.sh` → `run_all.sh` → `gen_reports.sh`, prints a markdown summary to
stdout and `$GITHUB_STEP_SUMMARY`, exposes `total`/`passed`/`failed` via
`$GITHUB_OUTPUT`, and **exits non-zero unless every package passed** so it can
be used as a release gate. Set `FAIL_ON_REGRESSION=0` for a report-only run.

```bash
TORNADO_SPEC="git+https://github.com/tornadoweb/tornado.git@my-branch" ./scripts/ci.sh
ONLY="flower bokeh" ./scripts/ci.sh    # restrict to specific packages
```

It commits nothing: results are read from the build log and the uploaded
`logs/`, `results/` and `coverage_html/` artifacts.

`.github/workflows/testbed.yml` drives it. Run it from the Actions tab with a
`tornado_spec` input, or call it as a reusable workflow from another repository
— which is how tornado's own release build uses it.

Each package runs as its own job. A failing package turns its own job red and
prints its full log there (passing packages fold theirs into a collapsed
group); the remaining packages and the final report still run. With
`fail_on_regression` off, per-package jobs stay green, like the report.

## Adding or changing a package

Everything about a package lives in its own directory under `packages/`; see
[`packages/README.md`](packages/README.md). Version pins are managed by
dependabot, which opens a pull request per bump; the `pins` workflow runs the
affected package so a bump that needs attention says so on its own PR.

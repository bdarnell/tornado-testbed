# Downstream Tornado Test-Suite Report

A snapshot of the **current state** of the harness: the 10 most popular Python
packages that depend on Tornado, each run in its own `uv`-managed Python 3.11
virtualenv against a chosen `TORNADO_SPEC`. Every run installs the package's
pinned version (from source, or the PyPI wheel where the source build needs a
JS toolchain or network assets), then forcibly upgrades `tornado` to the spec.

> Per-session history — what changed when and why, with before/after numbers —
> lives in [`notes/`](notes/). This file describes how things stand now.

## Current results (tornado 6.5.5)

| #  | Package        | GitHub ref | Tests run                  | Status | Time |
|----|----------------|------------|----------------------------|--------|------|
| 1  | streamlit      | 1.40.0     | 50 passed                  | PASS   | 7s   |
| 2  | bokeh          | 3.6.1      | 16 passed                  | PASS   | 6s   |
| 3  | jupyter_server | v2.14.2    | 970 passed, 17 skipped     | PASS   | 228s |
| 4  | notebook       | v7.2.2     | 6 passed                   | PASS   | 7s   |
| 5  | jupyterhub     | 5.2.1      | 194 passed                 | PASS   | 156s |
| 6  | distributed    | 2024.10.0  | 21 passed                  | PASS   | 4s   |
| 7  | flower         | v2.0.1     | 162 passed, 2 skipped      | PASS   | 6s   |
| 8  | ipykernel      | v6.29.5    | 140 passed, 20 skipped     | PASS   | 68s  |
| 9  | panel          | v1.5.3     | 40 passed, 2 skipped       | PASS   | 10s  |
| 10 | voila          | v0.5.8     | 2 passed                   | PASS   | 10s  |

**10/10 green.** Full output is in `logs/<package>.log`; machine-readable
results in `results/<package>.txt`; the table is reproducible with
`scripts/summarize.sh`.

The jupyter_server / jupyterhub / ipykernel suites drive **real Tornado test
servers** (live `ServerApp`s, a real MockHub + `configurable-http-proxy`, real
IPython kernels over ZeroMQ); the others run focused server-layer subsets. Each
package's `notes` field in `packages.json` records exactly what it exercises and
why its `test_cmd` is shaped the way it is.

## Coverage

HTML reports are in `coverage_html/<package>/` (per package) and
`coverage_html/merged/` (union, path-remapped to one canonical Tornado);
rebuild with `scripts/gen_reports.sh`. Merged Tornado coverage is **~61%**.

| Package        | tornado coverage |
|----------------|:----------------:|
| streamlit      | 45% |
| bokeh          | 39% |
| jupyter_server | 42% |
| notebook       | 23% |
| jupyterhub     | 42% |
| distributed    |  9% |
| flower         | 43% |
| ipykernel      |  7% |
| panel          | 31% |
| voila          | 20% |
| **merged**     | **61%** |

(ipykernel and distributed look low because they use only narrow slices of
Tornado — async primitives / the asyncio bridge, and the bare TCP layer,
respectively — but cover those slices well; see their `packages.json` notes.)

## Standing limitations & decisions

These are current facts about the harness, not one-off history — keep them in
mind before assuming a number can simply be pushed up.

- **`tornado.auth` is stuck at ~18%.** Flower is the *only* package here that
  imports `tornado.auth`, and its existing suite (run in full) only exercises
  the `authenticate` / `validate_auth_option` helpers and HTTP Basic auth — it
  never drives the OAuth2 login handlers
  (`GoogleOAuth2Mixin.get_authenticated_user`, `authorize_redirect`,
  `oauth2_request`), which is where most of `auth.py` lives. Moving this number
  requires *new* OAuth-flow tests, not just running more of what exists.

- **voila runs only `utils_test.py` (~20%) on purpose.** Its `tests/app` /
  `tests/server` suites drive real Tornado servers and would lift coverage to
  ~30% (websocket 63%), but the cold-start kernel-WebSocket tests deadlock
  intermittently in a ZeroMQ poll that ignores both `pytest-timeout`'s SIGALRM
  and a plain SIGTERM — i.e. they can hang the whole run. To opt in manually:
  install `pytest-tornasync pytest-timeout ipykernel` alongside the wheel and
  run `tests/app tests/server` under `timeout -s KILL 600`, deselecting the
  custom-template / papermill / xeus-C++ feature tests (see the voila note in
  `packages.json`).

- **System prerequisites for the live-server suites:** **node/npm** must be on
  PATH so jupyterhub can install/run `configurable-http-proxy`.

## How to re-use the harness

```bash
./scripts/setup.sh                         # clone all packages
./scripts/run_all.sh                       # run everything
./scripts/run_one.sh <name-or-index>       # run one
./scripts/summarize.sh                     # refresh results/summary.txt
./scripts/gen_reports.sh                   # rebuild coverage_html/

# Point it at any Tornado build:
TORNADO_SPEC="tornado==6.5.0"          ./scripts/run_all.sh
TORNADO_SPEC="tornado==7.0.0.dev1"     ./scripts/run_all.sh
TORNADO_SPEC="/abs/path/to/wheel.whl"  ./scripts/run_one.sh bokeh
```

Each call to `run_one.sh` builds a fresh per-package venv, so there is no state
carried between packages.

## Gotchas worth knowing if you extend the harness

- **`uv venv` has no `pip`** — test commands that shell out to `pip` must use
  `uv pip`.
- **setuptools_scm / hatch-vcs packages** (bokeh, distributed) want full tags;
  `setup.sh` fetches them.
- **Project-level `filterwarnings=error`** (the whole Jupyter stack) turns
  benign downstream warnings into failures. Prefer a *targeted*
  `-W ignore::Specific.Warning` over fighting the global filter or shrinking the
  test target.
- **`relative_files=true`** in a project's coverage config yields relative paths
  that break standalone `coverage html` (the report shows 0%); pass
  `--cov-config=/dev/null` to force absolute paths.
- **GC-timing `ResourceWarning`s** (e.g. panel's leaked server sockets) can be
  promoted to errors by pytest's unraisable-exception sweep even when every test
  passes; `-p no:unraisableexception` disables just that sweep.
- **Real-kernel (ZeroMQ) tests can deadlock** in a way that ignores SIGALRM and
  SIGTERM; wrap them in `timeout -s KILL` if you must run them unattended, and
  expect intermittency.
- **Orphaned test processes** from killed runs (voila kernels especially) pile
  up and contend for CPU — `pgrep -f pytest` before trusting timing.
- **Protobuf codegen** for streamlit is a hard prereq; the manifest's
  `setup_extra` hook runs `protoc` for that one package.

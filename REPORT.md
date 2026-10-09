# Downstream Tornado Test-Suite Report

A snapshot of the **current state** of the harness: the most popular Python
packages that depend on Tornado, each run in its own `uv`-managed Python 3.13
virtualenv against a chosen `TORNADO_SPEC`. Every run installs the package's
pinned version (from source, or the PyPI wheel where the source build needs a
JS toolchain or network assets), then forcibly upgrades `tornado` to the spec
and verifies that is what actually ends up imported.

> This file describes how things stand now. Per-package detail — what each one
> exercises and why its suite is shaped that way — lives in each
> [`packages/<name>/README.md`](packages/).

## Current results (tornado 6.5.10, Python 3.13)

| Package        | Ref        | Tests run                | Status | Time |
|----------------|------------|--------------------------|--------|------|
| bokeh          | 3.10.0     | 24 passed                | PASS   | 6s   |
| distributed    | 2026.8.0   | 21 passed                | PASS   | 5s   |
| flower         | v2.1.0     | 251 passed, 2 skipped    | PASS   | 6s   |
| ipykernel      | v7.3.0     | 181 passed, 26 skipped   | PASS   | 90s  |
| jupyter_server | v2.21.1    | 1136 passed, 34 skipped  | PASS   | 297s |
| jupyterhub     | 6.0.1      | 213 passed               | PASS   | 158s |
| mitmproxy      | v12.2.3    | 63 passed, 1 skipped     | PASS   | 7s   |
| notebook       | v7.6.2     | 6 passed                 | PASS   | 7s   |
| panel          | v1.9.4     | 49 passed, 2 skipped     | PASS   | 11s  |
| thumbor        | 7.8.0      | 636 passed, 9 skipped    | PASS   | 34s  |
| voila          | v0.5.13    | 2 passed                 | PASS   | 10s  |

**11/11 green.** mitmproxy's and thumbor's rows are from the runs that added
them; the rest are from the run that dropped streamlit, all against 6.5.10. In
the full run made when mitmproxy was added,
jupyter_server had one failure, `test_restart_kernel[jp_server_config0]`: it
gives a closed WebSocket one second to drop out of the kernel's connection
count, which it missed under load, and it passed 3/3 when re-run on its own.
Watch for it recurring before deselecting it. Full output is in
`logs/<package>.log`; machine-readable results in `results/<package>.txt`; the
table is reproducible with `scripts/summarize.sh`.

The jupyter_server / jupyterhub / ipykernel suites drive **real Tornado test
servers** (live `ServerApp`s, a real MockHub + `configurable-http-proxy`, real
IPython kernels over ZeroMQ), and mitmproxy drives mitmweb's real
`tornado.web.Application` over a live socket; the others run focused
server-layer subsets.

## How this is used

`scripts/ci.sh` and `.github/workflows/testbed.yml` both **exit non-zero unless
every package passes**, so this can gate a release. `FAIL_ON_REGRESSION=0` gives
the old report-only behaviour.

tornado's own `build.yml` calls `testbed.yml` as a reusable workflow on pushes
to release branches and on `v*` tags. Because a called workflow shares the
caller's run, the testbed installs the **exact wheel that run built** and
asserts its version is the one imported — see [`integration/`](integration/) for
the tornado-side patch and its reasoning.

The workflow runs packages as a job matrix (one per package, `fail-fast: false`)
and runs weekly against `master`, so drift surfaces between releases rather than
during one.

## Does the gate actually catch anything?

Yes, demonstrably — at jupyter_server 2.14.2 the harness caught
[tornado#3724](https://github.com/tornadoweb/tornado/issues/3724)
(`StaticFileHandler.allowed_symlink_directory` was set only in `initialize()`,
so subclasses replacing `initialize()` raised `AttributeError` on every
static-file request). Four tests failed on 6.5.9 and passed on 6.5.8 and 6.5.10.

**The current pin no longer trips it**: jupyter_server 2.21.1 changed
`FileFindHandler` enough that all four pass on 6.5.9. That is the cost of
tracking current downstream code, and it is the right trade — but it means a
green run is not by itself evidence the gate works.
[`packages/jupyter_server/README.md`](packages/jupyter_server/README.md) has the
replay procedure for getting that evidence back on demand.

## Coverage

Measured on the **weekly scheduled run** and on **pin-update pull requests**,
and left off elsewhere: the release gate's job is pass/fail, and `pytest-cov`
overhead buys it nothing. A manual dispatch can turn it on with the `coverage`
input.

HTML reports are built on demand and never committed. `scripts/gen_reports.sh`
writes `coverage_html/<package>/` and `coverage_html/merged/` (union,
path-remapped to one canonical Tornado), and CI uploads them as the
`coverage-html` artifact. It works with or without the per-package venvs: every
package records coverage against its own venv's copy of Tornado, and a `[paths]`
remap collapses those onto one canonical installation, which is also what lets
the job matrix render reports from nothing but the uploaded `.coverage` files.

### Coverage floors

Each package declares a `min_coverage` in its `package.env`. When a run
measures coverage, a package that comes in under its floor fails as
`COVERAGE_LOW` — even though its tests passed.

This catches the failure that no other signal here would: a new downstream
release moves or renames the files a `test.sh` names, the command keeps exiting
0, and it exercises almost none of Tornado. Everything looks green while the
package has quietly stopped testing anything. Arming this on pin-update PRs is
the point — that is exactly when it happens.

Floors sit roughly 20% under the measured value, so ordinary drift does not trip
them. They are only useful while they track reality, so the report flags any
package running well clear of its own floor.

| Package        | tornado coverage |
|----------------|:----------------:|
| bokeh          | 39% |
| distributed    |  9% |
| flower         | 43% |
| ipykernel      |  7% |
| jupyter_server | 42% |
| jupyterhub     | 36% |
| mitmproxy      | 51% |
| notebook       | 22% |
| panel          | 31% |
| thumbor        | 40% |
| voila          | 20% |
| **merged**     | **64%** |

(ipykernel and distributed look low because they use only narrow slices of
Tornado — async primitives / the asyncio bridge, and the bare TCP layer,
respectively — but cover those slices well; see their
`packages/<name>/README.md`.)

Merged coverage was 61% when streamlit was still in the set and fell to 59%
when it was dropped. Adding mitmproxy, now the single highest-coverage package
(51%), brought it back to 61%; adding thumbor took it to 64%, mostly by moving
`tornado.curl_httpclient` from 1% to 62% — no other package touches it.

## Standing limitations & decisions

These are current facts about the harness, not one-off history — keep them in
mind before assuming a number can simply be pushed up.

- **streamlit is gone.** It moved to Starlette/uvicorn in 1.57.0 and no longer
  depends on Tornado at all, so it failed the testbed's first selection
  criterion. mitmproxy replaced it; the selection reasoning is in
  [`packages/README.md`](packages/README.md).

- **`tornado.auth` is stuck at ~18%.** Flower is the *only* package here that
  imports `tornado.auth`, and its suite only exercises the `authenticate` /
  `validate_auth_option` helpers and HTTP Basic auth — it never drives the
  OAuth2 login handlers (`GoogleOAuth2Mixin.get_authenticated_user`,
  `authorize_redirect`, `oauth2_request`), which is where most of `auth.py`
  lives. Moving this number requires *new* OAuth-flow tests, not just running
  more of what exists.

- **voila runs only `utils_test.py` (~20%) on purpose.** Its `tests/app` /
  `tests/server` suites drive real Tornado servers and would lift coverage to
  ~30% (websocket 63%), but the cold-start kernel-WebSocket tests deadlock
  intermittently in a ZeroMQ poll that ignores both `pytest-timeout`'s SIGALRM
  and a plain SIGTERM — i.e. they can hang the whole run. See
  `packages/voila/README.md` to opt in by hand.

- **System prerequisites:** **node/npm** must be on PATH so jupyterhub can
  install/run `configurable-http-proxy`, and **gifsicle** and **jpegtran** for
  thumbor's image pipeline. CI installs the latter from thumbor's
  `apt_packages`; locally, thumbor's `setup.sh` stops with `SETUP_FAIL` if they
  are missing rather than letting ~10 tests fail with 504s.

- **Build-time dependencies are pinned** in `build-constraints.txt`. Packages do
  not pin their own build backends, so a backend release can stop a downstream
  pin from building at all — which looks like a testbed failure and says nothing
  about Tornado.

- **Coverage numbers in the table above are hand-updated.** The weekly run
  produces a `coverage-html` artifact, but nothing writes back into this file.
  Publishing the report somewhere linkable, so this table can stop being a
  transcription, is an open follow-up.

## Gotchas worth knowing if you extend the harness

- **`scripts/common.sh` enables `set -e`.** Guard any command whose non-zero
  exit you intend to handle (`run_tests || rc=$?`). An unguarded failure aborts
  before the result file is written, which makes a red package invisible to the
  gate rather than merely red.
- **`uv venv` has no `pip`** — test commands that shell out to `pip` must use
  `uv pip`.
- **setuptools_scm / hatch-vcs packages** (bokeh, distributed) want full tags;
  `setup.sh` fetches them.
- **Project-level `filterwarnings=error`** (the whole Jupyter stack, and panel)
  turns benign downstream warnings into failures. Prefer a *targeted*
  `-W ignore::Specific.Warning` over fighting the global filter or shrinking the
  test target. panel needed `pytest-xdist` installed purely so that its
  `pytest.mark.xdist_group` is a registered mark rather than a warning.
- **A missing optional dependency can look like a broken test.** flower's broker
  tests failed with `NameError: name 'Retry' is not defined` because
  `broker.py` imports it inside a `try/except ImportError` and `redis` was not
  installed. Installing the dependency beat deselecting 22 tests.
- **`relative_files=true`** in a project's coverage config yields relative paths
  that break standalone `coverage html` (the report shows 0%); pass
  `--cov-config=/dev/null` to force absolute paths.
- **A project's own `branch = True`** makes its coverage data impossible to
  combine with everyone else's statement data, and the merged report fails
  outright ("Can't combine branch coverage data with statement data") —
  leaving the *previous* merged HTML in place. thumbor's `.coveragerc` does
  this; `--cov-config=/dev/null` in its `test.sh` is the fix. Pass it for any
  new package too.
- **GC-timing `ResourceWarning`s** (e.g. panel's leaked server sockets) can be
  promoted to errors by pytest's unraisable-exception sweep even when every test
  passes; `-p no:unraisableexception` disables just that sweep.
- **Real-kernel (ZeroMQ) tests can deadlock** in a way that ignores SIGALRM and
  SIGTERM; wrap them in `timeout -s KILL` if you must run them unattended, and
  expect intermittency. `run_one.sh` retries once on `TIMEOUT` for this reason,
  and only on `TIMEOUT`.
- **Orphaned test processes** from killed runs (voila kernels especially) pile
  up and contend for CPU — `pgrep -f pytest` before trusting timing.
- **Dependency drift shows up as a permanent red run**, which hides the Tornado
  regressions the harness exists to find. Deselect that kind of failure, with
  the reason on the line above the deselect in the package's `test.sh`, so that
  a red package means a Tornado regression.
- **Drift can also break the *install*, not just the tests**, and a newer pin is
  not always the cure: hatchling 1.32.1 broke `hatch_jupyter_builder` for every
  version of jupyter_server and notebook at once. That is what
  `build-constraints.txt` is for.
- **Downstream can leave Tornado entirely.** streamlit did. Check that a package
  still imports Tornado before debugging why its suite stopped being useful.
- **A package needing generated code gets a `setup.sh` hook** — protobuf codegen
  for streamlit was the original case; flower's `redis` install is the current
  one.
- **A reusable workflow does not check itself out.** Under `workflow_call` the
  runner's workspace is the *caller's* repository, so a bare `actions/checkout`
  in `testbed.yml` fetches tornado, not the harness, and every step fails on a
  missing `scripts/`. The checkouts name `job.workflow_repository` and
  `job.workflow_sha` — the repository and commit of the workflow file defining
  the job — which is also correct for a dispatch, the schedule and pins.yml's
  local call. This only breaks when tornado calls us, so dispatching the
  workflow here proves nothing about it.

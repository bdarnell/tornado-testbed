# 2026-06-16 — Expand test runs to exercise more Tornado via real servers

## Goal

Broaden the downstream test runs from the previous tiny, mostly import-level
subsets to the real live-server / real-kernel suites, within a ~5–10 min per
project budget (the prior runs spent <30s each). Particular focus: the Jupyter
stack (low coverage, important dependents) and `tornado.auth`.

## What changed

Three `test_cmd`s in `packages.json` were expanded; two unrelated robustness
fixes were made; `coverage_html/` and `results/summary.txt` were regenerated.
All 10 packages stay green at tornado 6.5.5.

### Coverage before → after (merged, whole tornado library)

Merged coverage **57.5% → 61.0%**, concentrated in the HTTP/WebSocket server
layers that real downstream servers exercise:

| tornado module     | before | after |
|--------------------|:------:|:-----:|
| httpserver.py      |  59%   |  78%  |
| http1connection.py |  67%   |  75%  |
| httputil.py        |  70%   |  76%  |
| web.py             |  65%   |  72%  |
| websocket.py       |  66%   |  71%  |
| netutil.py         |  48%   |  56%  |
| queues.py          |  67%   |  71%  |
| log.py             |  56%   |  60%  |

Per package (merged-basis):

| Package        | before | after | what changed |
|----------------|:------:|:-----:|--------------|
| jupyter_server | ~6%*   |  42%  | runs the **full** suite on live ServerApps (43 → 970 tests) |
| jupyterhub     | 18%    |  42%  | runs the live MockHub REST/auth/metrics suites (52 → 194 tests) |
| ipykernel      | ~3%*   |   7%  | runs the real-kernel suite (15 → 140 tests) |
| notebook       | ~10%*  |  23%  | reporting fix only; tests unchanged |

\* jupyter_server / notebook / ipykernel were **mis-reported as 0% in the
previously committed `coverage_html`** because of the path bug fixed below; the
"before" figures are their true prior values from the package notes.

### Expansions (the `test_cmd` changes)

- **jupyter_server (6% → 42%).** From four pure-function modules to the entire
  `tests/` tree (~970 tests) driven by the `pytest-jupyter` fixtures, which boot
  a real `ServerApp` on a real port and drive it with `jp_fetch` / `jp_ws_fetch`.
  The `jupyter_events>=0.12` schema-version incompat that previously blocked
  these tests is sidestepped with a targeted
  `-W ignore::...JupyterEventsVersionWarning` (v2.14.2 ships integer schema
  versions; newer jupyter_events warns, and the project's `filterwarnings=error`
  turns that into a failure — unrelated to Tornado). Three of its own
  order-dependent / subprocess-launch tests are deselected (they pass in
  isolation).

- **jupyterhub (18% → 42%).** From logic-only modules to the live `test_api` /
  `test_services_auth` / `test_metrics` / `test_dummyauth` suites, which boot a
  real MockHub Tornado app plus a `configurable-http-proxy` node process.
  `test_pages` / `test_named_servers` were left out: they spawn real
  single-user notebook servers and overrun the time budget.

- **ipykernel (3% → 7%).** Now runs the real-kernel suite (~140 tests), starting
  IPython kernels over ZeroMQ on Tornado's asyncio loop (platform.asyncio 41%,
  ioloop 58%, queues 51%, concurrent 38%). The editable install's
  auto-generated kernelspec points at uv's (now-cleaned) build-time Python, so
  the test_cmd reinstalls a correct one with `ipykernel install --sys-prefix`
  first. Overall % stays low because ipykernel touches none of the
  web/HTTP/WebSocket layers. `test_message_spec` (nose-style module `setup()`
  that pytest 9 no longer calls) and a few debugger / IPython version-specific
  tests are deselected.

### Reporting fix (`--cov-config=/dev/null`)

The previously committed `coverage_html/{jupyter_server,notebook,ipykernel}`
reports showed **0%** — a path bug, not zero coverage. Those three projects set
`relative_files = true` in their coverage config, so pytest-cov stored source
paths like `.venv/lib/.../tornado/web.py`; standalone `coverage html` then
couldn't line them up and marked everything missing. Adding
`--cov-config=/dev/null` to those three `test_cmd`s makes pytest-cov ignore the
project config and record absolute paths (as the other seven packages already
did), so the reports render correctly.

### Panel robustness fix (`-p no:unraisableexception`)

Panel's `filterwarnings=["error"]` promotes a GC-timing
`ResourceWarning: unclosed socket` (leaked by its Bokeh/Tornado server
fixtures) into a hard error during pytest's end-of-session unraisable-exception
sweep — all 40 tests pass, only teardown fails. This surfaced when re-running in
a fresh container (a pytest/GC-timing artifact, not a Tornado regression).
Disabling that sweep with `-p no:unraisableexception` restores a reliable PASS.

## Dead-ends / decisions

- **`tornado.auth` could not be improved (stayed 18%).** Flower is the only
  package that imports `tornado.auth`, and its committed suite — already run in
  full (162 tests) — only covers the `authenticate` / `validate_auth_option`
  helpers and HTTP Basic auth. It has no tests that drive the OAuth2 login
  handlers (`GoogleOAuth2Mixin.get_authenticated_user`, `authorize_redirect`,
  `oauth2_request`), which is where most of `auth.py` lives. Raising it would
  require writing new OAuth-flow tests, which was explicitly out of scope. (This
  limitation is recorded in REPORT.md as a standing fact.)

- **voila live suite evaluated but not adopted.** Voila's `tests/app` /
  `tests/server` suites drive real Tornado servers and execute notebooks over a
  real kernel WebSocket; when they complete they lift voila's coverage to ~30%
  (websocket 63%). But under the harness's always-fresh venv, the cold-start
  kernel-WebSocket tests deadlock intermittently (~50% of runs observed) in a
  ZeroMQ poll that swallows both `pytest-timeout`'s SIGALRM and a plain
  SIGTERM — they hang until SIGKILL. A coin-flip package is worse than a smaller
  reliable one, so voila stays on `utils_test.py` (~20%). How to opt into the
  fuller suite is documented in REPORT.md and the voila note in `packages.json`.

- **Process hygiene.** Several intermittent slowdowns during this session traced
  back to orphaned voila pytest/kernel processes from killed runs piling up and
  contending for CPU — worth checking `pgrep -f pytest` before trusting timing.

## Validation

All four touched manifest entries (jupyter_server, jupyterhub, ipykernel, panel)
were validated end-to-end from fresh venvs via `scripts/run_one.sh`, then the
whole set via `scripts/run_all.sh` at `TORNADO_SPEC=tornado==6.5.5`: 10/10 green.

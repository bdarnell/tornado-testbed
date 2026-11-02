# Package definitions

One directory per downstream package. These are the committed definitions; the
sources they describe are cloned into `../checkouts/` by `scripts/setup.sh` and
are not tracked.

## Layout

```
packages/<name>/
  requirements.txt   the pinned downstream release
  package.env        metadata, as strict key=value
  test.sh            the test command
  setup.sh           optional post-install hook
  README.md          what it exercises, and why its suite is shaped that way
  constraints.lock   generated: every other dependency, frozen (see below)
```

### requirements.txt

A single `name==version` requirement. This is the **only** place the version
lives, and the file dependabot updates. For `install_method=pypi` it is also
what gets installed.

### package.env

Parsed as strict `key=value`, never sourced — the matrix job needs `repo` and
`tag_template` before any package's own code runs.

| key | required | meaning |
|---|---|---|
| `repo` | yes | git URL to clone. |
| `tag_template` | yes | how to build the git tag from the version, e.g. `v{version}` or `{version}`. |
| `subdir` | yes | directory within the checkout to run tests from (`.` for most). |
| `install_method` | no | `editable` (default) or `pypi`. |
| `pypi_extra_deps` | no | extra specs to install alongside, for `pypi` installs. |
| `apt_packages` | no | space-separated Debian/Ubuntu packages the workflow installs before the run, for command-line tools the suite shells out to. Pair it with a `setup.sh` check so a missing tool is a `SETUP_FAIL`, not a red test. |
| `min_coverage` | no | percent of Tornado this package must cover. Below it, a *passing* run fails as `COVERAGE_LOW`. |

There is no ranking: packages are run and reported in alphabetical order, and
selected by name.

**The git ref is derived, never stored:** `tag_template` applied to the version
in `requirements.txt`. Storing both invites them to disagree, and a testbed
running a different commit than the version it claims is worse than useless.
`scripts/validate_packages.py --check-refs` confirms the derived tag resolves
upstream.

### test.sh

The test command, as a script rather than a string in a data file. That matters
most for the deselects: each one sits next to the comment explaining why it is
not a Tornado failure, which is the piece of this repo that needs the most
upkeep.

Run from the checkout, inside the package's venv, with the Tornado under test
already force-installed. Coverage flags come from `COV_ARGS`, which the harness
exports empty when a run is not measuring coverage.

### min_coverage

A passing test run is not by itself evidence that anything was tested. When a
new downstream release moves or renames the files `test.sh` names, the command
can keep exiting 0 while exercising almost none of Tornado — which looks
identical to a healthy run in every other signal the harness collects.

`min_coverage` closes that gap: when a run measures coverage, a package that
comes in under its floor fails as `COVERAGE_LOW` even though its tests passed.
The floors sit roughly 20% under the measured value, so ordinary drift does not
trip them and a collapse does.

They only mean anything while they track reality. When coverage genuinely
improves, raise the floor — the report prints a reminder when a package is
running well clear of its own. Dependabot never touches these values, which is
the point: a pin bump that guts the test command fails on its own pull request.

### constraints.lock

Every distribution in the package's tested environment except Tornado and the
package itself, as `name==version`, frozen from a passing-or-not refresh run.
`run_one.sh` exports it as `UV_CONSTRAINT`, so the package install, `setup.sh`,
the harness's own pytest install and any `uv pip install` inside `test.sh` all
resolve to the locked versions. Without it, a new pytest-asyncio or IPython
reaches the weekly run and the release gate the day it is published, and shows
up as a red package that has nothing to do with Tornado.

**Never edit it by hand.** The `locks` workflow regenerates all of them weekly,
and whenever a pin bump lands on main, by running every package with
`LOCK_MODE=refresh` against stable Tornado, and proposes the result as a single
pull request whose description lists any package that did not pass. That PR is
where drift gets handled. To regenerate one locally:

```bash
LOCK_MODE=refresh ./scripts/run_one.sh ipykernel
```

A lock records the pin and the Python minor it was made for. If either differs
from the run (most often: a dependabot bump not yet followed by a refresh), the
lock is **stale** and the package resolves unlocked, as every package did
before locks existed. That is a warning, not a failure: it does not change
which Tornado is tested. The result records `lock=unlocked` and the report
lists those packages.

It is not `*.txt` on purpose: dependabot reads every `.txt` in a directory it
watches as a requirements file, and would open a pull request per locked
transitive dependency.

## Selection criteria

These are the most popular Python packages that depend directly on Tornado,
chosen by a combination of GitHub stars and PyPI download volume. Each:

- declares `tornado` in its own install requirements (direct, not transitive)
- is popular on GitHub (stars) and/or PyPI (downloads)
- has an active repository with a runnable test suite

### Removed

- **streamlit** — was the most popular entry, and the single largest contributor to merged
  Tornado coverage (~45%). It migrated to Starlette/uvicorn in **1.57.0**;
  1.64.0 declares no dependency on Tornado and contains no `tornado` imports at
  all. It no longer meets the first criterion, so it was dropped rather than
  frozen at 1.56.0 — a pin that could never move again would have gone on
  reporting coverage for code the ecosystem is leaving behind.

  It was replaced by **mitmproxy**; see below.

### Added

- **mitmproxy** — replaced streamlit. Candidates were PyPI packages
  whose *current* release still declares `tornado` directly, then judged on
  popularity and on whether the Tornado-facing part of their suite runs
  unattended:

  | candidate  | stars | Tornado usage | verdict |
  |------------|------:|---------------|---------|
  | mitmproxy  | ~40k  | `mitmweb` is a `tornado.web` app: REST handlers, xsrf + signed cookies, WebSocket server *and* client, gzip transform | **chosen** — most-starred direct dependent, actively maintained, and its web suite runs in seconds over a live server |
  | luigi      | ~18k  | the central scheduler's small `tornado.web` server | runner-up; one test file and a few handlers, so far less signal |
  | thumbor    | ~10k  | Tornado app plus `AsyncHTTPClient` / `curl_httpclient` image loading | also added (below), for `curl_httpclient` |
  | jupyterlab |  ~15k | `jupyter_server` extension | almost entirely the Tornado surface jupyter_server and notebook already cover |
  | salt       |  ~15k | event bus / netapi on Tornado | suite needs a running master/minion; impractical here |

  jupyter_client, ipyparallel and terminado also qualify, but each overlaps
  the Jupyter stack already in the set and is less popular than mitmproxy.

  mitmproxy caps Tornado tightly (`<=6.5.5` at 12.2.3) and raises the cap as it
  validates new releases — exactly the consumer a pre-release gate should be
  checking. See [`mitmproxy/README.md`](mitmproxy/README.md).

- **thumbor** — added alongside mitmproxy, not instead of anything. Its
  Tornado usage is narrower, but it is the only package in the set that
  exercises `tornado.curl_httpclient`; without it a regression there could not
  turn anything red. It brings one system tool, `gifsicle`, declared in
  `apt_packages`. See [`thumbor/README.md`](thumbor/README.md).

## Adding a package

```bash
mkdir packages/<name>
# write requirements.txt, package.env, test.sh (chmod +x), README.md
python3 scripts/validate_packages.py --check-refs
scripts/setup.sh <name> && scripts/run_one.sh <name>
```

Add `/packages/<name>` to the `directories:` list in `.github/dependabot.yml`;
`validate_packages.py` fails until you do.

## Skipping policy

Where a package's full suite is impractical to run — it needs a JS toolchain,
Selenium, Playwright, a database, or hours of wall clock — `test.sh` narrows to
the modules that exercise the Tornado integration points, and the package's
`README.md` records what was dropped and why.

The rule that matters: **a red package must mean a Tornado regression.** A test
that fails for any other reason gets deselected with its reason recorded, because
a package that is permanently red hides the regressions the testbed exists to
find.

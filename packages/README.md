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
| `rank` | yes | popularity rank, 1-10. Orders the reports and doubles as a selector: `run_one.sh 7`. |
| `repo` | yes | git URL to clone. |
| `tag_template` | yes | how to build the git tag from the version, e.g. `v{version}` or `{version}`. |
| `subdir` | yes | directory within the checkout to run tests from (`.` for most). |
| `install_method` | no | `editable` (default) or `pypi`. |
| `pypi_extra_deps` | no | extra specs to install alongside, for `pypi` installs. |

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

## Selection criteria

These are the most popular Python packages that depend directly on Tornado,
chosen by a combination of GitHub stars and PyPI download volume. Each:

- declares `tornado` in its own install requirements (direct, not transitive)
- is popular on GitHub (stars) and/or PyPI (downloads)
- has an active repository with a runnable test suite

### Removed

- **streamlit** — was rank 1, and the single largest contributor to merged
  Tornado coverage (~45%). It migrated to Starlette/uvicorn in **1.57.0**;
  1.64.0 declares no dependency on Tornado and contains no `tornado` imports at
  all. It no longer meets the first criterion, so it was dropped rather than
  frozen at 1.56.0 — a pin that could never move again would have gone on
  reporting coverage for code the ecosystem is leaving behind.

  Restoring the set to ten means redoing the selection work for a replacement,
  which has not been done yet.

## Adding a package

```bash
mkdir packages/<name>
# write requirements.txt, package.env, test.sh (chmod +x), README.md
python3 scripts/validate_packages.py --check-refs
scripts/setup.sh <name> && scripts/run_one.sh <name>
```

Give it a `rank` no other package uses, and add it to `.github/dependabot.yml`
if the `directories:` glob does not already cover it.

## Skipping policy

Where a package's full suite is impractical to run — it needs a JS toolchain,
Selenium, Playwright, a database, or hours of wall clock — `test.sh` narrows to
the modules that exercise the Tornado integration points, and the package's
`README.md` records what was dropped and why.

The rule that matters: **a red package must mean a Tornado regression.** A test
that fails for any other reason gets deselected with its reason recorded, because
a package that is permanently red hides the regressions the testbed exists to
find.

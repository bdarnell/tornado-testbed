# Integrating with tornado's release process

`tornado-release-gate.patch` is the change to `tornadoweb/tornado` that makes
this testbed part of its release build. It has to be applied by someone with
push access to that repository.

```bash
cd /path/to/tornado
git apply /path/to/tornado-testbed/integration/tornado-release-gate.patch
```

It touches two files:

- **`.github/workflows/build.yml`** — adds a `downstream` job that calls
  `tornadoweb/tornado-testbed/.github/workflows/testbed.yml@main` as a reusable
  workflow.
- **`.github/zizmor.yml`** — adds `tornadoweb/*: ref-pin`, without which
  tornado's own zizmor lint rejects a `uses:` reference that is not hash-pinned.

## Why this shape

`build.yml` already runs on pushes to release branches (`branch[0-9]*`) and on
`v*` tags, and already builds the sdist and wheels. That makes it the natural
host: the release-branch push is the moment when there is still time to act on a
downstream failure.

A **called** reusable workflow runs as jobs inside the caller's workflow run, so
`actions/download-artifact` resolves against that run. The testbed therefore
installs the exact wheel the release build just produced, and asserts that the
version it read from the wheel filename is the version that ends up imported.
A cross-repo `workflow_dispatch` could not do that — it would re-resolve a git
ref in a separate run, and would need a token in tornado's secrets besides.

## What it deliberately does not do

The `downstream` job is **not** in `upload_pypi`'s `needs`. A flaky downstream
suite must not be able to wedge a release upload. The testbed is a signal to
read before pushing a tag, not a blocking gate on publishing.

It is also skipped on forks (`if: github.repository == 'tornadoweb/tornado'`),
since a fork has no reason to spend that CI time.

## Referencing by branch rather than SHA

The `uses:` reference is `@main`, which is why the zizmor policy change is
needed. Pinning a SHA would mean a release build gating on whatever package pins
the testbed had months ago — the opposite of what this is for. `tornadoweb/*` is
the same trust boundary as the `actions/*` and `pypa/*` entries already in that
policy file.

## Before applying

This repository must already live at `tornadoweb/tornado-testbed`. GitHub does
not follow repository-transfer redirects for `uses:` references, so the transfer
has to land first. It must also stay public, and the org's Actions policy must
allow reusable workflows from it.

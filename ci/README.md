# CI integration

This directory holds the GitHub Actions workflow that is meant to live in the
**tornado** repo, not here. It's checked in so it can be reviewed and version
controlled alongside the harness; copy it over when you're ready.

## `tornado-downstream-testbed.yml` → tornado repo

Install it into `tornadoweb/tornado` as a workflow_dispatch action:

```bash
cp ci/tornado-downstream-testbed.yml \
   /path/to/tornado/.github/workflows/downstream-testbed.yml
```

Then from the tornado repo's **Actions → downstream-testbed → Run workflow**:

- pick the **tornado branch** to test in the "Use workflow from" dropdown
  (the workflow installs whatever branch you select), and
- optionally set **testbed_ref** to run a non-`main` branch of this harness.

The job checks out this harness, installs the selected tornado source into each
downstream package's isolated env via `TORNADO_SPEC`, runs their suites, prints
a summary table to the build log + job summary, and uploads `logs/`, `results/`
and `coverage_html/` as the `testbed-results` artifact. Nothing is committed.

## `.github/workflows/testbed.yml` (this repo)

A self-test of the harness. Run it from this repo's Actions tab and give it a
`tornado_ref` (branch/tag/SHA); it tests against
`git+https://github.com/tornadoweb/tornado.git@<ref>`. Same script
(`scripts/ci.sh`), same artifacts.

## How it stays thin

Both workflows are intentionally minimal — checkout, `setup-uv`, run
`scripts/ci.sh`, upload artifacts. All behaviour (which packages, summary
rendering, step-summary/output wiring, not committing anything) lives in
`scripts/ci.sh` so it can be changed without editing YAML in two repos.

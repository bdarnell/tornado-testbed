# jupyterhub

Multi-user Jupyter server, ~8k stars; Tornado-based.

## What it exercises

Runs against a real MockHub Tornado application -- the `app` fixture boots the
Hub plus a `configurable-http-proxy` process and serves real HTTP. ~194 tests.

- `tornado.options` for CLI/config parsing (uncommon among these packages)
- `tornado.gen` and `tornado.concurrent`, heavily, for OAuth and auth-provider
  coroutine flows
- `tornado.log` for structured log formatting

## Prerequisite

**node/npm must be on PATH.** `setup.sh` installs `configurable-http-proxy`
globally via npm if it is missing.

## Why the suite is shaped this way

`test_pages` and `test_named_servers` are excluded because they spawn real
single-user notebook servers and blow the time budget. The selected files give
the bulk of the `tornado.web` coverage without them.

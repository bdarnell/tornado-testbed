# mitmproxy

Interactive HTTPS proxy, ~40k stars — the most-starred project that still
declares `tornado` directly. `mitmweb`, its browser UI, is a Tornado
application. Added in place of streamlit (see `packages/README.md`).

## What it exercises

`test/mitmproxy/tools/web/` drives mitmweb's real `tornado.web.Application`
through `tornado.testing.AsyncHTTPTestCase`, so it goes over a live server
socket rather than calling handlers directly:

- `tornado.web` — a REST API of `RequestHandler`s, `xsrf_cookies` with a custom
  cookie name and `xsrf_cookie_kwargs`, signed cookies (`cookie_secret`, with
  `create_signed_value` in the tests), and a `GZipContentEncoding` subclass that
  extends `CONTENT_TYPES`
- `tornado.websocket` on **both** sides: a `WebSocketHandler` that broadcasts
  flow updates, exercised by `websocket_connect` clients in the tests
- `tornado.httpclient` / `simple_httpclient` via the test client
- `tornado.escape` for JSON encoding

It also reaches into one private name, `RequestHandler._unimplemented_method`,
to tell which HTTP verbs a handler overrides. A refactor of `web.py` that
renames it breaks mitmweb, and this suite will say so.

## Why the suite is shaped this way

The rest of mitmproxy's suite tests the proxy core, which is built on asyncio
and its own protocol stack, not Tornado. Only `tools/web` touches Tornado, and
it runs in seconds, so all of it runs.

`setup.sh` installs the test tooling at the versions mitmproxy itself pins (its
`dev` dependency group, which is not an installable extra). pytest 9 refuses
mitmproxy's `pyproject.toml` outright: it treats the
`[tool.pytest.individual_coverage]` table as native-TOML pytest config and
rejects the mix with `[tool.pytest.ini_options]`. That is a pytest/mitmproxy
disagreement, not a Tornado failure.

One test skips: `test_process_icon` needs
`mitmproxy_rs.process_info.executable_icon`, which is only built on macOS and
Windows.

## Tornado upper bound

mitmproxy pins Tornado with a tight cap (`tornado>=6.5.0,<=6.5.5` at 12.2.3) and
raises it as it validates new releases. The harness force-installs the Tornado
under test regardless, which is the point: a regression shows up here before
mitmproxy's next cap bump would ship it to users.

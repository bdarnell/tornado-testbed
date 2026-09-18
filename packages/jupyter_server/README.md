# jupyter_server

Core backend for Jupyter Notebook / JupyterLab; Tornado is its HTTP engine.

## What it exercises

The full suite runs against **live Tornado servers**: the `pytest-jupyter`
fixtures (`jp_serverapp`, `jp_fetch`, `jp_ws_fetch`) boot a real `ServerApp` on
a real port. ~970 tests, the longest run in the testbed.

- `tornado.testing` as jupyter_server's own test base infrastructure
- `tornado.websocket` for kernel and terminal communication channels

Tornado coverage from this package alone reaches the web/HTTP layers most
broadly of any entry here (websocket, web, iostream, httpserver).

## Why this package matters most

It is the testbed's detector for
[tornado#3724](https://github.com/tornadoweb/tornado/issues/3724):
`StaticFileHandler.allowed_symlink_directory`, added in 6.5.9, was set only in
`initialize()`, so subclasses that replace `initialize()` -- like
jupyter_server's `FileFindHandler` -- raised `AttributeError` on every
static-file request.

Four tests in this run fail on 6.5.9 and pass on 6.5.8 and 6.5.10:

- `tests/base/test_handlers.py::test_static_handler`
- `tests/extension/test_handler.py::test_base_url`
- `tests/services/kernelspecs/test_api.py::test_get_kernel_resource_file`
- `tests/services/kernelspecs/test_api.py::test_get_nonexistant_resource`

That makes this the end-to-end check on whether the harness itself still works
as a gate:

```bash
ONLY="jupyter_server" TORNADO_SPEC="tornado==6.5.9"  ./scripts/ci.sh   # must fail
ONLY="jupyter_server" TORNADO_SPEC="tornado==6.5.10" ./scripts/ci.sh   # must pass
```

## Deselects

Every `--deselect` in `test.sh` carries its reason inline. They fall into two
kinds: jupyter_server's own order-dependent or subprocess-launching tests, and
one case of dependency drift that is red on every Tornado version. Both would
otherwise make this package permanently red and hide real regressions.

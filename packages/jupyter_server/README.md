# jupyter_server

Core backend for Jupyter Notebook / JupyterLab; Tornado is its HTTP engine.

## What it exercises

The full suite runs against **live Tornado servers**: the `pytest-jupyter`
fixtures (`jp_serverapp`, `jp_fetch`, `jp_ws_fetch`) boot a real `ServerApp` on
a real port. ~1136 tests, the longest run in the testbed.

- `tornado.testing` as jupyter_server's own test base infrastructure
- `tornado.websocket` for kernel and terminal communication channels

Tornado coverage from this package alone reaches the web/HTTP layers most
broadly of any entry here (websocket, web, iostream, httpserver).

## Why this package matters most

It is the package that proved the testbed works. At jupyter_server 2.14.2 it
caught [tornado#3724](https://github.com/tornadoweb/tornado/issues/3724):
`StaticFileHandler.allowed_symlink_directory`, added in 6.5.9, was set only in
`initialize()`, so subclasses that replace `initialize()` -- like
jupyter_server's `FileFindHandler` -- raised `AttributeError` on every
static-file request. Four tests failed on 6.5.9 and passed on 6.5.8 and 6.5.10:

- `tests/base/test_handlers.py::test_static_handler`
- `tests/extension/test_handler.py::test_base_url`
- `tests/services/kernelspecs/test_api.py::test_get_kernel_resource_file`
- `tests/services/kernelspecs/test_api.py::test_get_nonexistant_resource`

**The current pin no longer detects it.** All four pass on 6.5.9 under
jupyter_server 2.21.1, which changed `FileFindHandler` enough not to trip the
bug. That is the normal cost of tracking current downstream code, and it is the
right trade -- the testbed exists to protect the code people are running now --
but it means a routine green run is no longer evidence that the gate can catch a
real regression.

### Validating the harness

To get that evidence back, pin this package temporarily to the release that
still trips the bug. This is a deliberate manual procedure, not something a
normal run does:

```bash
sed -i 's/^jupyter_server==.*/jupyter_server==2.14.2/' packages/jupyter_server/requirements.txt
rm -rf checkouts/jupyter_server && ./scripts/setup.sh jupyter_server

TORNADO_SPEC="tornado==6.5.9"  ./scripts/run_one.sh jupyter_server   # must FAIL, 4 tests
TORNADO_SPEC="tornado==6.5.10" ./scripts/run_one.sh jupyter_server   # must PASS

git checkout packages/jupyter_server/requirements.txt
```

The 6.5.9 run should show
`AttributeError: 'FileFindHandler' object has no attribute
'allowed_symlink_directory'`. If it does not, something in the harness has
stopped reporting real failures and that is worth chasing before trusting a
green release gate.

(2.14.2 needs the `hatchling<1.32.1` entry in `build-constraints.txt` to install
at all; it is already there.)

## Deselects

Every `--deselect` in `test.sh` carries its reason inline. They fall into two
kinds: jupyter_server's own order-dependent or subprocess-launching tests, and
one case of dependency drift that is red on every Tornado version. Both would
otherwise make this package permanently red and hide real regressions.

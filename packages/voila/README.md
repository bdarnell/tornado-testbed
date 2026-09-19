# voila

Render Jupyter notebooks as standalone apps, ~5.4k stars; Tornado-based server.

## What it exercises

- `tornado.template`, heavily, for converting notebook cells to HTML output
  (the second-highest template usage after flower)
- `tornado.websocket` for kernel communication

Does not use `tornado.auth`, `tornado.options` or `tornado.wsgi`.

## Why `install_method=pypi`

The source build fetches bundled CSS from a URL that 403s in sandboxed
environments. The harness installs the published wheel and runs the test files
from the checkout.

## Why only `utils_test.py`

This is the testbed's clearest deliberate trade-off, so it is worth stating
plainly.

voila's `tests/app` and `tests/server` suites *do* drive real Tornado servers
(via the `pytest-tornasync` `http_server_client` fixture) and execute notebooks
over a real kernel WebSocket. When they complete they lift this package's
Tornado coverage from ~20% to ~30% (websocket 63%, iostream 43%, web 32%).

They are not the default because, under the harness's always-fresh venv, the
cold-start kernel-WebSocket tests deadlock in roughly half of runs, inside a
ZeroMQ poll that swallows both `pytest-timeout`'s SIGALRM and a plain SIGTERM.
The run hangs until SIGKILL. A coin-flip package in an unattended gate is worse
than a narrow one.

To opt in by hand when investigating Tornado WebSocket behaviour: install
`pytest-tornasync pytest-timeout ipykernel` alongside the wheel and run
`tests/app tests/server` under `timeout -s KILL 600`, deselecting the
custom-template / papermill / xeus-C++ feature tests that need assets absent
from the wheel.

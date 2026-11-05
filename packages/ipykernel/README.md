# ipykernel

IPython kernel for Jupyter, ~650 stars; uses Tornado via jupyter_client.

## What it exercises

Starts **real IPython kernels over ZeroMQ**, driven by Tornado's asyncio event
loop. ~140 tests.

Only Tornado's async primitives and the event-loop bridge:
`tornado.gen`, `tornado.locks`, `tornado.queues`, `tornado.concurrent` and
`tornado.platform.asyncio`. None of the web framework, HTTP server, TCP server
or WebSocket layers -- Tornado is reached entirely through jupyter_client's
kernel protocol.

Overall coverage therefore reads low while the modules it does use are covered
well (`platform.asyncio`, `ioloop`, `queues`). That is the point of keeping it:
nothing else here exercises the asyncio bridge this hard.

## Install

From 7.4 the test dependencies are a PEP 735 dependency group, not an extra,
so `setup.sh` installs them with `uv pip install --group test`. The harness's
`.[test]` install still "succeeds" -- uv only warns about the missing extra --
so without that hook the suite fails at conftest import with no
`pytest_asyncio`.

## Deselects

All four are environment issues, not Tornado; each carries its reason inline in
`test.sh`.

## pytest-asyncio loop scope

`test.sh` passes `-o asyncio_default_fixture_loop_scope=function`. ipykernel
leaves that option unset under `filterwarnings = ["error", ...]`, so
pytest-asyncio 1.4.1.post1's configure-time deprecation warning becomes an
INTERNALERROR (exit 3, zero tests run). All of the suite's async fixtures are
function-scoped, so the setting only silences the warning. Drop it once an
ipykernel release sets the option itself.

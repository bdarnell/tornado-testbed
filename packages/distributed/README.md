# distributed

Dask distributed scheduler, ~1.6k stars; its communications layer uses Tornado.

## What it exercises

The only entry here that uses Tornado's **bare TCP networking layer** without
the HTTP/web framework at all: `tornado.iostream`, `tornado.tcpserver`,
`tornado.tcpclient`. No `tornado.web`, `tornado.websocket` or
`tornado.httpclient`.

Overall Tornado coverage from this package looks low, but the networking modules
it does touch are covered well -- which is the part worth watching for
regressions here.

## Why the suite is shaped this way

The full suite is multi-hour. `test.sh` pins one small module that exercises the
communications layer.

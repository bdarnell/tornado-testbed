# bokeh

Bokeh interactive visualization, ~19k stars; the Bokeh server is built on
Tornado.

## What it exercises

- `tornado.websocket` for push updates to the browser
- `tornado.queues` for buffering session messages
- `tornado.locks` for per-session serialization

Does not use `tornado.testing` or `tornado.auth`.

## Why the suite is shaped this way

The full bokeh suite requires selenium and node, so `test.sh` targets the
Tornado-specific server tests.

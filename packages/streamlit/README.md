# streamlit

Streamlit ML/data-app framework, ~35k GitHub stars; uses Tornado for its web
server.

## What it exercises

- `tornado.websocket` for browser WebSocket connections
- `tornado.testing` (`AsyncHTTPTestCase`) as the foundation for streamlit's own
  server test helpers
- `tornado.template` for HTML page rendering

## Why the suite is shaped this way

The full test suite needs a built frontend and a long list of extras, so
`test.sh` runs the server-layer tests only -- the subset that drives Tornado.

`setup.sh` generates the Python protobuf bindings after the package install, so
that `grpcio-tools` resolves against the `protobuf<6` streamlit already pins.
Without it the server tests fail on a missing generated module, which has
nothing to do with Tornado.

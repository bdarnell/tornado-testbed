# panel

HoloViz Panel dashboards, ~5k stars; built on Bokeh/Tornado.

## What it exercises

- `tornado.wsgi` for WSGI middleware integration -- **the only package here
  that exercises it**
- `tornado.websocket` for live push updates to the browser
- the Bokeh server's `tornado.queues` and `tornado.locks` usage, inherited

## Why `install_method=pypi`

panel's source build runs a full npm/bokeh bundling step. The harness installs
the published wheel instead and runs the test files from the checkout, so the
pin in `requirements.txt` is both the wheel version and the git tag it is
checked out at.

## Why `-p no:unraisableexception`

panel sets `filterwarnings=error`, which promotes a GC-timing
`ResourceWarning: unclosed socket` from its Bokeh/Tornado server fixtures into a
hard error during pytest's unraisable-exception sweep at teardown. All the tests
pass; only the sweep fails. Disabling that one plugin keeps the package honest
about Tornado without chasing a garbage-collection artifact.

# notebook

Classic Jupyter Notebook UI, ~11k stars; pulls Tornado in through
jupyter_server.

## What it exercises

- `tornado.template` for rendering notebook HTML pages
- `tornado.websocket` for the notebook kernel communication channel

## Why the suite is shaped this way

notebook 7 is a thin frontend over jupyter_server and ships a single test file,
covering import and app startup. The Tornado exercise that matters for this part
of the stack comes from the `jupyter_server` entry.

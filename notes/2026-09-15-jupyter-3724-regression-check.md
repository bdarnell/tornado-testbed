# 2026-09-15 — Make the jupyter_server run a clean detector for tornado#3724

## Goal

[tornadoweb/tornado#3724](https://github.com/tornadoweb/tornado/issues/3724):
JupyterLab fails to start on Tornado 6.5.9 with

```
AttributeError: 'FileFindHandler' object has no attribute 'allowed_symlink_directory'
```

Fixed in 6.5.10. The upstream report names four jupyter_server tests that
caught it. This session checked that the testbed's jupyter_server entry runs
them and actually turns red on 6.5.9 — i.e. that the harness would have caught
this regression before the release went out.

## The bug

6.5.9's symlink hardening (`web: Do not follow symlinks out of the static
directory`) added `StaticFileHandler.allowed_symlink_directory` and set it
*only in* `initialize()`. jupyter_server's `FileFindHandler` defines its own
`initialize()` that never calls `super().initialize()` (it searches a list of
directories, so `self.root` is a tuple of paths, not a string), so the
attribute was never set and every static-file request raised `AttributeError`.
6.5.10 gives the attribute a class-level default of `None` and resolves it in
`validate_absolute_path` against the root it was handed.

## What changed

`packages.json`, jupyter_server entry only:

- **One added deselect: `tests/test_utils.py::test_check_version`.** It fails
  on *every* Tornado version, so it was making the whole entry red regardless
  of Tornado and drowning the signal we care about. It is pure dependency
  drift: the test calls `check_version(1.0, "1.0.1")` with a float, and
  `jupyter_server.utils.check_version` only catches `TypeError`, which is what
  older `packaging` raised for a non-string. Current `packaging` (26.3 here)
  raises `InvalidVersion` instead, which propagates. Nothing to do with
  Tornado — deselected, in the same spirit as the three deselects already
  there, so that a red jupyter_server run means a Tornado regression.
- **`notes` updated** to record that deselect and to name the four #3724
  tests, so the next person can see what this entry is expected to catch.

The test command still runs the whole `tests/` tree; the four tests from the
issue were already inside it and needed no additions.

## Verification

`TORNADO_SPEC="tornado==<v>" ./scripts/run_one.sh jupyter_server`, one fresh
venv per version, with the updated command:

| Tornado | harness status | pytest result |
|---------|----------------|---------------|
| 6.5.8   | PASS (rc 0)    | 969 passed, 17 skipped, 15 deselected (4:07) |
| 6.5.9   | **FAIL** (rc 1) | **4 failed**, 965 passed, 17 skipped, 15 deselected (4:09) |
| 6.5.10  | PASS (rc 0)    | 969 passed, 17 skipped, 15 deselected (4:06) |

The four failures on 6.5.9 are exactly the ones named in the issue, with the
same failure modes:

```
FAILED tests/base/test_handlers.py::test_static_handler - AttributeError: 'FileFindHandler' object has no attribute 'allowed_symlink_directory'
FAILED tests/extension/test_handler.py::test_base_url[jp_server_config0-/test_prefix/] - tornado.httpclient.HTTPClientError: HTTP 500: Internal Server Error
FAILED tests/services/kernelspecs/test_api.py::test_get_kernel_resource_file - tornado.httpclient.HTTPClientError: HTTP 403: Forbidden
FAILED tests/services/kernelspecs/test_api.py::test_get_nonexistant_resource - assert False
```

Only `test_static_handler` shows the `AttributeError` directly; the other three
go through a live server, so the handler's 500/403 is what reaches the client.
`test_get_nonexistant_resource` asserts a 404 and gets a 403 instead — the
`AttributeError` is raised before the missing file is ever looked up.

## Decisions / limits

- **The four tests were not added to `test_cmd` as explicit node IDs.** The
  entry already runs all of `tests/`, so listing them again would only run them
  twice. They are recorded in the entry's `notes` instead.
- **JupyterLab itself is still not in the testbed**, even though it is where
  the bug was reported. jupyter_server is the package that owns
  `FileFindHandler`, and it reproduces the failure, so it is the cheaper
  detector; adding a JupyterLab entry would need its JS build toolchain.
- **`notebook` (v7.2.2) does not catch this** — checked, its entry still
  passes on 6.5.9: it runs only `tests/test_app.py` (6 import/startup tests)
  and never serves a static file.
- The pinned `jupyter_server` ref stays at v2.14.2. The upstream PR in the
  issue thread (jupyter-server/jupyter_server#1703) hit the same four tests on
  a newer tree, and v2.14.2 reproduces them, so there is no reason to bump.
- `results/summary.txt`, `coverage_html/` and `REPORT.md`'s results table were
  left at their committed 6.5.5 state; this session ran one package, not the
  full matrix. The next full run will show 969 rather than 970 passing for
  jupyter_server, from the new deselect. `REPORT.md` did get one new gotcha
  bullet: dependency drift that reds out a package hides the Tornado
  regressions the harness is for, so deselect it with the reason recorded.

#!/usr/bin/env bash
# jupyter_server: full suite against live Tornado servers
#
# Run from the package's checkout by scripts/run_one.sh, inside that package's
# venv, with the Tornado under test already force-installed.
set -euo pipefail

# --cov-config=/dev/null: this project's coverage config sets
# relative_files=true, and those relative paths make a standalone
# `coverage html` report read 0%. Forcing absolute paths keeps it usable.
#
# Coverage flags come from the harness: run_one.sh exports COV_ARGS empty when
# the run is not measuring coverage, so a release gate does not pay for it. The
# default below applies when this script is run by hand.
read -ra cov <<<"${COV_ARGS---cov-config=/dev/null --cov=tornado --cov-report=term-missing}"

# The FULL jupyter_server suite, which drives live Tornado servers through the
# pytest-jupyter fixtures (jp_serverapp / jp_fetch / jp_ws_fetch boot a real
# ServerApp on a real port). ~970 tests. This is the testbed's most valuable
# package and its detector for tornado#3724 -- see README.md.
#
# Every deselect below is a test that fails for a reason that is not Tornado.
# Leaving one in would make this package permanently red, hiding the Tornado
# regressions it exists to find.
args=(
    tests/
    -q
    -p no:cacheprovider

    # jupyter_server 2.14.2 ships integer event-schema versions that newer
    # jupyter_events warns about, and the project's filterwarnings=error turns
    # that warning into a failure. Unrelated to Tornado.
    -W 'ignore::jupyter_events.utils.JupyterEventsVersionWarning'

    # jupyter_server's own order-dependent and subprocess-launching tests.
    # All three pass in isolation.
    --deselect tests/extension/test_launch.py
    --deselect tests/test_serverapp.py::test_urls
    --deselect tests/test_serverapp.py::test_browser_open_files

    # Dependency drift, red on every Tornado version: it calls
    # check_version(1.0, ...) with a float, and current packaging raises
    # InvalidVersion where it used to raise the TypeError check_version catches.
    --deselect tests/test_utils.py::test_check_version
)

python -m pytest "${args[@]}" "${cov[@]}"

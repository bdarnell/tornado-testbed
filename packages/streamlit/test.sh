#!/usr/bin/env bash
# streamlit: server-layer unit tests
#
# Run from the package's checkout by scripts/run_one.sh, inside that package's
# venv, with the Tornado under test already force-installed.
set -euo pipefail

# Coverage flags come from the harness: run_one.sh exports COV_ARGS empty when
# the run is not measuring coverage, so a release gate does not pay for it. The
# default below applies when this script is run by hand.
read -ra cov <<<"${COV_ARGS---cov=tornado --cov-report=term-missing}"

# The full suite needs a built frontend and a long list of extras. These are the
# server-layer tests, which are the ones that drive Tornado.
args=(
    # Drop the project's own addopts (coverage of streamlit itself, and options
    # we do not want here), and quiet the app's own logging.
    -o addopts=
    -o log_level=WARNING

    tests/streamlit/web/server/routes_test.py
    tests/streamlit/web/server/browser_websocket_handler_test.py
    tests/streamlit/web/server/stats_handler_test.py
    tests/streamlit/web/server/component_request_handler_test.py
    tests/streamlit/web/server/upload_file_request_handler_test.py
    tests/streamlit/web/server/websocket_headers_test.py
    tests/streamlit/web/server/app_static_file_handler_test.py

    -q
)

python -m pytest "${args[@]}" "${cov[@]}"

#!/usr/bin/env bash
# jupyterhub: live-server REST API, service-auth and metrics suites
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

# Live-server suites: the `app` fixture boots a real MockHub Tornado
# application plus a configurable-http-proxy node process and serves real HTTP.
# ~194 tests.
args=(
    # test_pages and test_named_servers are left out deliberately: they spawn
    # real single-user notebook servers and blow the time budget. These four
    # give the bulk of the tornado.web coverage without them.
    jupyterhub/tests/test_api.py
    jupyterhub/tests/test_services_auth.py
    jupyterhub/tests/test_metrics.py
    jupyterhub/tests/test_dummyauth.py

    -q
    -p no:cacheprovider
)

python -m pytest "${args[@]}" "${cov[@]}"

#!/usr/bin/env bash
# notebook: app startup tests
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

# notebook 7 is a thin JupyterLab-based frontend over jupyter_server, and
# tests/test_app.py is the only test file it ships.
python -m pytest tests/test_app.py -x -q "${cov[@]}"

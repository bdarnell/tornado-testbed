#!/usr/bin/env bash
# voila: utility tests against the published wheel
#
# Run from the package's checkout by scripts/run_one.sh, inside that package's
# venv, with the Tornado under test already force-installed.
set -euo pipefail

# Coverage flags come from the harness: run_one.sh exports COV_ARGS empty when
# the run is not measuring coverage, so a release gate does not pay for it. The
# default below applies when this script is run by hand.
read -ra cov <<<"${COV_ARGS---cov=tornado --cov-report=term-missing}"

# Only utils_test.py, by design: the live-server suites deadlock intermittently
# and would make this package a coin flip in an unattended gate. README.md has
# the full reasoning and how to opt into the fuller suite by hand.
python -m pytest -o addopts= tests/utils_test.py -x -q "${cov[@]}"

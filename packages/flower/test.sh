#!/usr/bin/env bash
# flower: full suite (small and self-contained)
#
# Run from the package's checkout by scripts/run_one.sh, inside that package's
# venv, with the Tornado under test already force-installed.
set -euo pipefail

# Coverage flags come from the harness: run_one.sh exports COV_ARGS empty when
# the run is not measuring coverage, so a release gate does not pay for it. The
# default below applies when this script is run by hand.
read -ra cov <<<"${COV_ARGS---cov=tornado --cov-report=term-missing}"

# flower's whole suite is small and self-contained, so run all of it.
#
# Deliberately no -x: a gate should report every failure in one go rather than
# stop at the first, and this suite takes seconds.
python -m pytest tests/ -q "${cov[@]}"

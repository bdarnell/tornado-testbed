#!/usr/bin/env bash
# panel: io-layer tests against the published wheel
#
# Run from the package's checkout by scripts/run_one.sh, inside that package's
# venv, with the Tornado under test already force-installed.
set -euo pipefail

# Coverage flags come from the harness: run_one.sh exports COV_ARGS empty when
# the run is not measuring coverage, so a release gate does not pay for it. The
# default below applies when this script is run by hand.
read -ra cov <<<"${COV_ARGS---cov=tornado --cov-report=term-missing}"

# Tests run from the checkout, against the wheel in site-packages -- the source
# build runs a full npm/bokeh bundling step. See README.md.
args=(
    # Drop the project's own addopts.
    -o addopts=

    # panel sets filterwarnings=error, which promotes a GC-timing
    # "ResourceWarning: unclosed socket" from its Bokeh/Tornado server fixtures
    # into a hard error during pytest's unraisable-exception sweep at teardown.
    # Every test passes and only the sweep fails, so disable just that plugin.
    -p no:unraisableexception

    panel/tests/test_util.py
    panel/tests/io/test_state.py
    panel/tests/io/test_document.py
    panel/tests/io/test_location.py
    panel/tests/io/test_notebook.py
    panel/tests/io/test_reload.py

    -q
)

python -m pytest "${args[@]}" "${cov[@]}"

#!/usr/bin/env bash
# bokeh: Tornado server tests
#
# Run from the package's checkout by scripts/run_one.sh, inside that package's
# venv, with the Tornado under test already force-installed.
set -euo pipefail

# Coverage flags come from the harness: run_one.sh exports COV_ARGS empty when
# the run is not measuring coverage, so a release gate does not pay for it. The
# default below applies when this script is run by hand.
read -ra cov <<<"${COV_ARGS---cov=tornado --cov-report=term-missing}"

# The bokeh server's own Tornado integration tests. The rest of bokeh's suite
# wants selenium and a node toolchain.
uv pip install -q pytest-timeout pytest-asyncio

args=(
    # The project does not set asyncio_mode and these tests are bare async defs.
    -o asyncio_mode=auto
    # bokeh's fixtures trip pytest's own warnings, which its config would
    # otherwise promote to errors.
    -W 'ignore::pytest.PytestWarning'

    tests/unit/bokeh/server/test_tornado__server.py

    -q
)

python -m pytest "${args[@]}" "${cov[@]}"

#!/usr/bin/env bash
# mitmproxy: mitmweb's Tornado application tests
#
# Run from the package's checkout by scripts/run_one.sh, inside that package's
# venv, with the Tornado under test already force-installed.
set -euo pipefail

# Coverage flags come from the harness: run_one.sh exports COV_ARGS empty when
# the run is not measuring coverage, so a release gate does not pay for it. The
# default below applies when this script is run by hand.
read -ra cov <<<"${COV_ARGS---cov=tornado --cov-report=term-missing}"

# Only mitmweb (tools/web) is built on Tornado; the proxy core is plain asyncio.
# The whole directory runs in seconds, so all of it runs.
args=(
    # Drop the project's own addopts (--capture=no --color=yes): they only make
    # the log harder to read.
    -o addopts=
    # mitmproxy's coverage config omits "*platform*", which would hide
    # tornado/platform/asyncio.py from the per-module report.
    --cov-config=/dev/null

    test/mitmproxy/tools/web/

    -q
)

python -m pytest "${args[@]}" "${cov[@]}"

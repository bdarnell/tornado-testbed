#!/usr/bin/env bash
# ipykernel: full suite, driving real IPython kernels over ZeroMQ
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

# ipykernel's full suite, which starts real IPython kernels over ZeroMQ driven
# by Tornado's asyncio event loop. ~140 tests.
args=(
    tests/
    -q
    -p no:cacheprovider

    # nose-style module setup() that pytest no longer calls, so this module's
    # kernel client stays None.
    --deselect tests/test_message_spec.py

    # Needs debugpy.
    --deselect tests/test_debugger.py::test_attach_debug

    # Platform and version specific.
    --deselect tests/test_eventloop.py::test_asyncio_interrupt
    --deselect tests/test_start_kernel.py::test_ipython_start_kernel_userns
)

python -m pytest "${args[@]}" "${cov[@]}"

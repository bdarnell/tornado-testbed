#!/usr/bin/env bash
# ipykernel: test dependencies, and a working kernelspec.
set -uo pipefail

# Since 7.4 ipykernel's test toolchain (pytest-asyncio, flaky, psutil,
# pytest-timeout, ...) lives in the `test` dependency group in pyproject.toml,
# not an extra. uv accepts the harness's `.[test]` with only a warning and
# installs none of it, so the suite would die at conftest import. This one is
# fatal: without it the run says nothing about Tornado. It runs before the
# harness installs pytest, which then leaves the group's pin alone.
if ! uv pip install -q --group test; then
    echo "could not install ipykernel's test dependency group" >&2
    exit 1
fi

# The editable install's auto-generated kernelspec points at uv's build-time
# python, which is gone by the time the tests run. Reinstall a correct one.
#
# Deliberately non-fatal: this mirrors the original manifest, and if the
# kernelspec really is unusable the tests themselves will say so more clearly
# than a setup failure would.
if ! python -m ipykernel install --sys-prefix --name python3 >/dev/null 2>&1; then
    echo "WARNING: could not reinstall the python3 kernelspec" >&2
fi

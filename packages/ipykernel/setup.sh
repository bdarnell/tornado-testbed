#!/usr/bin/env bash
# The editable install's auto-generated kernelspec points at uv's build-time
# python, which is gone by the time the tests run. Reinstall a correct one.
#
# Deliberately non-fatal: this mirrors the original manifest, and if the
# kernelspec really is unusable the tests themselves will say so more clearly
# than a setup failure would.
set -uo pipefail

if ! python -m ipykernel install --sys-prefix --name python3 >/dev/null 2>&1; then
    echo "WARNING: could not reinstall the python3 kernelspec" >&2
fi

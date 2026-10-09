#!/usr/bin/env bash
# Install mitmproxy's test tooling at the versions mitmproxy itself pins.
#
# They live in the `dev` dependency group in pyproject.toml, which is not an
# extra, so the harness's editable install does not pull them in.
#
# The pytest pin is the one that matters. pytest 9 refuses to start at all on
# this pyproject.toml: it reads the [tool.pytest.individual_coverage] table as
# native-TOML pytest config and rejects having that alongside
# [tool.pytest.ini_options]. That is a disagreement between pytest and
# mitmproxy's config, not a Tornado failure. This runs before the harness
# installs pytest, which then leaves the pinned one alone.
set -euo pipefail

uv pip install -q \
    pytest==8.4.2 \
    pytest-asyncio==1.2.0 \
    pytest-timeout==2.4.0 \
    hypothesis==6.130.6 \
    requests==2.32.5

#!/usr/bin/env bash
# thumbor: optional extras, test dependencies, and a check for the command-line
# tools its image pipeline shells out to.
set -euo pipefail

# Without gifsicle every animated-GIF request comes back 504 and ~10 handler
# and engine tests fail; without jpegtran the doctor test does. Neither has
# anything to do with Tornado, so a missing tool must stop the run here, as a
# SETUP_FAIL, rather than surface later as a red package. CI installs them from
# apt_packages in package.env.
missing=()
for tool in gifsicle jpegtran; do
    command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "thumbor needs these on PATH: ${missing[*]}" >&2
    echo "(Debian/Ubuntu: apt-get install gifsicle libjpeg-turbo-progs)" >&2
    exit 1
fi

# The harness's editable install takes no extras. `all` brings pycurl -- the
# whole reason thumbor is here: without it the CurlAsyncHTTPClient tests
# cannot run -- plus opencv and the image-format plugins. `tests` is the test
# toolchain (pytest<8, preggy, redis, ...). This runs before the harness
# installs pytest, which then leaves the pinned one alone.
uv pip install -q -e ".[all,tests]"

# Fail here, not halfway through the suite, if pycurl did not come with it.
python -c 'import pycurl'

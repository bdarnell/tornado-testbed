#!/usr/bin/env bash
# thumbor: optional extras, test dependencies, and a check for the command-line
# tool its image pipeline shells out to.
set -euo pipefail

# Without gifsicle every animated-GIF request comes back 504 and ~10 handler
# and engine tests fail, for reasons that have nothing to do with Tornado. So a
# missing gifsicle stops the run here, as a SETUP_FAIL, rather than surfacing
# later as a red package. CI installs it from apt_packages in package.env.
#
# Other tools thumbor can use are deliberately not required: its jpegtran
# tests skip themselves unless exiftool is present too, and the ffmpeg (GIFV)
# tests are deselected in test.sh.
if ! command -v gifsicle >/dev/null 2>&1; then
    echo "thumbor needs gifsicle on PATH (Debian/Ubuntu: apt-get install gifsicle)" >&2
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

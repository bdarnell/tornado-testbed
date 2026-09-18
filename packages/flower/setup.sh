#!/usr/bin/env bash
# flower's broker tests import Retry from redis.asyncio.retry.
#
# flower/utils/broker.py does that import inside a try/except ImportError, so
# without redis installed the name is simply never bound and 22 tests in
# tests/unit/utils/test_broker.py fail with "NameError: name 'Retry' is not
# defined". flower's own test extra does not pull redis in.
#
# Installing it is the right fix rather than deselecting those tests: they pass
# once the optional dependency is present, and deselecting would drop the whole
# Redis broker surface from the run for a reason that has nothing to do with
# Tornado.
set -euo pipefail

uv pip install -q redis

#!/usr/bin/env bash
# JupyterHub's live-server tests need the configurable-http-proxy node binary on
# PATH. node/npm are assumed present (they are on GitHub's ubuntu runners).
set -euo pipefail

if ! command -v configurable-http-proxy >/dev/null 2>&1; then
    npm install -g configurable-http-proxy
fi

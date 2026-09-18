#!/usr/bin/env bash
# streamlit's protobuf bindings are generated, not committed, and the server
# tests import them.
#
# This runs after the package install so grpcio-tools resolves against the
# protobuf<6 that streamlit already pinned, rather than dragging in a newer one.
set -euo pipefail

uv pip install -q grpcio-tools
cd ..
python -m grpc_tools.protoc \
    --proto_path=proto \
    --python_out=lib \
    proto/streamlit/proto/*.proto

#!/usr/bin/env bash
# Builds the Obsidian plugin inside a Linux Docker container to produce
# the same binary as CI (reproducible build verification).
#
# Usage:
#   ./build_plugin_docker.sh
#
# Output: ./build/main.js
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR"
DART_SDK="3.11.0"
OUT_DIR="$ROOT/build"

ACCOUNT_SERVICE_URL="https://api.rhyolite.nogipx.dev"
SYNC_SERVICE_URL="https://sync.rhyolite.nogipx.dev"

if [ -z "$ACCOUNT_SERVICE_URL" ] || [ -z "$SYNC_SERVICE_URL" ]; then
  echo "ERROR: ACCOUNT_SERVICE_URL and SYNC_SERVICE_URL must be set"
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "=== Building plugin in Docker (dart:$DART_SDK on linux/amd64) ==="

docker run --rm \
  --platform linux/amd64 \
  -v "$ROOT:/workspace" \
  -w /workspace \
  -e RELEASE=1 \
  -e USE_FVM=0 \
  -e OBSIDIAN_VAULT=/tmp/obsidian-build \
  "dart:$DART_SDK" \
  bash -c "
    dart pub get && \
    cd packages/client/rhyolite_client_obsidian && \
    dart run bin/build.dart \
      --dart-define=ACCOUNT_SERVICE_URL=$ACCOUNT_SERVICE_URL \
      --dart-define=SYNC_SERVICE_URL=$SYNC_SERVICE_URL && \
    cp /tmp/obsidian-build/rhyolite-sync/main.js /workspace/build/main.js
  "

echo ""
echo "=== Build complete ==="
echo "Output: $OUT_DIR/main.js"
echo ""
echo "SHA-256:"
sha256sum "$OUT_DIR/main.js"

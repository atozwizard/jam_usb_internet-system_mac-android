#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:a:h}"
OUT_DIR="${SCRIPT_DIR}/bin/arm64-v8a"
mkdir -p "$OUT_DIR"

cd "$SCRIPT_DIR"
GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "${OUT_DIR}/knock-relay" ./cmd/knock-relay

echo "${OUT_DIR}/knock-relay"

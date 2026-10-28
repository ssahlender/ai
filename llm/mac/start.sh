#!/usr/bin/env bash
# Starts ollama serve on the MacBook Air M4. Usage: ./start.sh
set -euo pipefail

PORT="${OLLAMA_HOST_PORT:-11434}"
# shellcheck source=../shared/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../shared/common.sh"

OLLAMA_BIN="${OLLAMA_BIN:-$(find_bin ollama || true)}"
if [ -z "$OLLAMA_BIN" ]; then
  echo "ollama not found in PATH or the Homebrew prefixes - install it or set OLLAMA_BIN" >&2
  exit 1
fi

# by port, not by command line: the graphify instance on 11438 is also an "ollama serve"
if [ -n "$(pids_on_port "$PORT")" ]; then
  echo "something already listens on $PORT. Stop it first: ../stop.sh" >&2
  exit 1
fi

echo "Starting ollama serve on port $PORT (flash-attention on, q8_0 KV cache)..."
exec env \
  OLLAMA_FLASH_ATTENTION=1 \
  OLLAMA_KV_CACHE_TYPE=q8_0 \
  OLLAMA_HOST="127.0.0.1:$PORT" \
  "$OLLAMA_BIN" serve

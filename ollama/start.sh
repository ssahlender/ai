#!/usr/bin/env bash
# Starts ollama serve on the MacBook Air M4. Usage: ./start.sh
set -euo pipefail

PORT="${OLLAMA_HOST_PORT:-11434}"

if pgrep -f "ollama serve" >/dev/null 2>&1; then
  echo "ollama serve is already running. Stop it first: ./stop.sh" >&2
  exit 1
fi

echo "Starting ollama serve on port $PORT (flash-attention on, q8_0 KV cache)..."
exec env \
  OLLAMA_FLASH_ATTENTION=1 \
  OLLAMA_KV_CACHE_TYPE=q8_0 \
  OLLAMA_HOST="127.0.0.1:$PORT" \
  ollama serve

#!/usr/bin/env bash
# Starts ollama serve on the MacBook Air M4. Usage: ./start.sh
set -euo pipefail

PORT="${OLLAMA_HOST_PORT:-11434}"

# Non-interactive shells (ssh, launchd, cron) do not get Homebrew's PATH, so a bare
# `ollama` fails there even though it works in a terminal. Resolve it explicitly.
OLLAMA_BIN=""
for c in "$(command -v ollama 2>/dev/null || true)" /opt/homebrew/bin/ollama /usr/local/bin/ollama; do
  if [ -n "$c" ] && [ -x "$c" ]; then OLLAMA_BIN="$c"; break; fi
done
if [ -z "$OLLAMA_BIN" ]; then
  echo "ollama not found in PATH, /opt/homebrew/bin or /usr/local/bin - install it or set OLLAMA_BIN" >&2
  exit 1
fi

if pgrep -f "ollama serve" >/dev/null 2>&1; then
  echo "ollama serve is already running. Stop it first: ./stop.sh" >&2
  exit 1
fi

echo "Starting ollama serve on port $PORT (flash-attention on, q8_0 KV cache)..."
exec env \
  OLLAMA_FLASH_ATTENTION=1 \
  OLLAMA_KV_CACHE_TYPE=q8_0 \
  OLLAMA_HOST="127.0.0.1:$PORT" \
  "$OLLAMA_BIN" serve

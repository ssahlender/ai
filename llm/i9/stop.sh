#!/usr/bin/env bash
# stop.sh — stop the local model stack on this machine, whichever way it was started:
# llama-swap (9082), llama-server (9080 or one llama-swap spawned), local-proxy.py (9081).
# --all also stops the cloud proxies claude-providers.sh starts (ocg-proxy 4099, nvidia-proxy 4098).
# Usage: ./stop.sh [--all]
#
# SIGTERM, not -9, so llama-swap can shut down the model it has loaded instead of orphaning it.
set -euo pipefail

kill_port() {
  local port="$1" name="$2" pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids=$(lsof -ti ":$port" -sTCP:LISTEN 2>/dev/null || true)
  elif command -v fuser >/dev/null 2>&1; then
    pids=$(fuser "${port}/tcp" 2>/dev/null || true)
  fi
  if [ -n "$pids" ]; then
    kill $pids 2>/dev/null || true
    echo "$name stopped (port $port)"
  else
    echo "$name not running (port $port)"
  fi
}

kill_port "${IK_LLAMA_SWAP_PORT:-9082}" "llama-swap"
if pkill -f "llama-server" 2>/dev/null; then echo "llama-server stopped"; else echo "llama-server not running"; fi
kill_port "${IK_LLAMA_AGENT_PORT:-9081}" "local-proxy"

if [ "${1:-}" = "--all" ]; then
  kill_port 4099 "ocg-proxy"
  kill_port 4098 "nvidia-proxy"
fi

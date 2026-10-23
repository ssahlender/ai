#!/usr/bin/env bash
# Stops llama-swap and the agent-facing proxy pointed at it (reverses llama-swap-setup.sh).
# Usage: ./llama-swap-stop.sh
#
# SIGTERM (not -9) so llama-swap gets to shut down whatever model it currently has loaded
# cleanly, rather than leaving an orphaned llama-server process behind.
#
# After this, local-proxy.py is down. Go back to the manual single-model setup with
# ./start.sh i9 <mode> as usual — it restarts local-proxy.py pointed at llama-server's own
# port (9080) on its own.
set -euo pipefail

kill_port() {
  local port="$1" name="$2"
  local killed=0
  if command -v fuser >/dev/null 2>&1; then
    if fuser -k "${port}/tcp" 2>/dev/null; then
      killed=1
    fi
  elif command -v lsof >/dev/null 2>&1; then
    local pids
    pids=$(lsof -ti ":$port" 2>/dev/null || true)
    if [ -n "$pids" ]; then
      kill $pids 2>/dev/null && killed=1 || true
    fi
  fi
  if [ "$killed" -eq 1 ]; then
    echo "$name stopped (port $port)"
  else
    echo "$name not running (port $port)"
  fi
}

kill_port "${IK_LLAMA_SWAP_PORT:-9082}" "llama-swap"
kill_port "${IK_LLAMA_AGENT_PORT:-9081}" "local-proxy"

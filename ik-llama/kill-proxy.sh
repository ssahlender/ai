#!/usr/bin/env bash
# kill-proxy.sh — stop ocg-proxy.py (4099) and local-proxy.py (9081)
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
      kill -9 $pids 2>/dev/null && killed=1 || true
    fi
  fi
  if [ "$killed" -eq 1 ]; then
    echo "$name killed"
  else
    echo "$name not running"
  fi
}

kill_port 4099 "ocg-proxy"
kill_port 4098 "nvidia-proxy"
kill_port 9081 "local-proxy"

#!/usr/bin/env bash
# stop.sh — stop mlx_lm.server
# macOS's BSD fuser doesn't support GNU's `-k PORT/tcp` syntax, so use lsof.
set -euo pipefail
PORT="${MLX_PORT:-8090}"
PIDS="$(lsof -ti "tcp:${PORT}" 2>/dev/null || true)"
if [ -n "$PIDS" ]; then
  kill $PIDS
  echo "mlx_lm.server killed"
else
  echo "mlx_lm.server not running"
fi

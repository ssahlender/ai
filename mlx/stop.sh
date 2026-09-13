#!/usr/bin/env bash
# stop.sh — stop mlx_lm.server
set -euo pipefail
PORT="${MLX_PORT:-8090}"
fuser -k "${PORT}/tcp" 2>/dev/null && echo "mlx_lm.server killed" || echo "mlx_lm.server not running"

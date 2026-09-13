#!/usr/bin/env bash
# Starts mlx_lm.server on the MacBook Air M4. Usage: ./start.sh <mode>
set -euo pipefail

MODE="${1:-}"
PORT="${MLX_PORT:-8090}"
REASONING_EFFORT="${MLX_REASONING_EFFORT:-low}"
MAX_TOKENS="${MLX_MAX_TOKENS:-4096}"

# shortname|display name|HF repo|context window (informational, for setup-agent.sh)
MODES=(
  "qwen38-27b|Qwen3.8-27B 4bit|mlx-community/Qwen3.8-27B-4bit|131072"
)

usage() {
  echo "Usage: $0 <mode>" >&2
  echo "Modes:" >&2
  for m in "${MODES[@]}"; do
    IFS='|' read -r SN NAME REPO CTX <<< "$m"
    printf "  %-12s %s (%s)\n" "$SN" "$NAME" "$REPO" >&2
  done
  exit 1
}

[ -n "$MODE" ] || usage

if pgrep -f "mlx_lm.server" >/dev/null 2>&1; then
  echo "mlx_lm.server is already running. Stop it first: ./stop.sh" >&2
  exit 1
fi

FOUND=
for m in "${MODES[@]}"; do
  IFS='|' read -r SN NAME REPO CTX <<< "$m"
  if [ "$SN" = "$MODE" ]; then
    FOUND=1
    echo "Starting $NAME on port $PORT (reasoning_effort=$REASONING_EFFORT, max_tokens=$MAX_TOKENS)..."
    exec mlx_lm.server \
      --model "$REPO" \
      --host 0.0.0.0 \
      --port "$PORT" \
      --max-tokens "$MAX_TOKENS" \
      --chat-template-args "{\"reasoning_effort\": \"$REASONING_EFFORT\"}"
  fi
done

[ -n "$FOUND" ] || { echo "Unknown mode: $MODE" >&2; usage; }

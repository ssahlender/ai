#!/usr/bin/env bash
# Stops ONLY the extraction-only ollama instance (the one on $GRAPHIFY_OLLAMA_PORT).
# The daily-driver instance on 11434 is never touched.
set -euo pipefail

PORT="${GRAPHIFY_OLLAMA_PORT:-11438}"
PIDS="$(lsof -ti "tcp:$PORT" 2>/dev/null || true)"

if [ -z "$PIDS" ]; then
  echo "nothing listening on $PORT (the daily-driver instance on 11434 is unaffected)" >&2
  exit 0
fi

# shellcheck disable=SC2086
kill $PIDS 2>/dev/null || true
sleep 1
if lsof -ti "tcp:$PORT" >/dev/null 2>&1; then
  echo "still listening on $PORT — escalate manually" >&2
  exit 1
fi
echo "extraction-only instance on $PORT stopped; 11434 untouched."

#!/usr/bin/env bash
# Starts llama-server on i9-13900 (Debian). Usage: ./start-i9.sh [qwen36|gemma4|qwen36u|supergemma4]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
PORT=9080
MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "Usage: $0 [qwen36|gemma4|qwen36u|supergemma4]" >&2
  exit 1
fi

if pgrep -x llama-server >/dev/null 2>&1; then
  echo "llama-server is already running. Stop it first." >&2
  exit 1
fi

start_model() {
  local name="$1" model="$2"
  echo "Starting $name on port $PORT..."
  "$SERVER" \
    -m "$MODELS_DIR/$model" \
    -ngl 0 \
    --threads 8 \
    --threads-batch 16 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram 16384 \
    -crs 0.5 \
    --port $PORT \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

case "$MODE" in
  qwen36)      start_model "Qwen3.6 35B-A3B"           "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf" ;;
  gemma4)      start_model "Gemma4 26B-A4B"            "gemma-4-26B-A4B-it-UD-Q5_K_M.gguf" ;;
  qwen36u)     start_model "Qwen3.6 35B-A3B Uncensored" "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf" ;;
  supergemma4) start_model "SuperGemma4 26B Uncensored" "supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf" ;;
  *) echo "Usage: $0 [qwen36|gemma4|qwen36u|supergemma4]" >&2; exit 1 ;;
esac

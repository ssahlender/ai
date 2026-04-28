#!/usr/bin/env bash
# Starts llama-server on i9-13900 (Debian). Usage: ./start-i9.sh [qwen36|gemma4|qwen36u|supergemma4]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "Usage: $0 [qwen36|gemma4|qwen36u|supergemma4]" >&2
  exit 1
fi

if pgrep -x llama-server >/dev/null 2>&1; then
  echo "llama-server is already running. Stop it first." >&2
  exit 1
fi

start_qwen36() {
  echo "Starting Qwen3.6 35B-A3B on port 9080..."
  "$SERVER" \
    -m "$MODELS_DIR/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf" \
    -ngl 0 \
    --threads 8 \
    --threads-batch 16 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram 16384 \
    -crs 0.5 \
    --port 9080 \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

start_gemma4() {
  echo "Starting Gemma4 26B-A4B on port 9081..."
  "$SERVER" \
    -m "$MODELS_DIR/gemma-4-26B-A4B-it-UD-Q5_K_M.gguf" \
    -ngl 0 \
    --threads 8 \
    --threads-batch 16 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram 16384 \
    -crs 0.5 \
    --port 9081 \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

start_qwen36u() {
  echo "Starting Qwen3.6 35B-A3B Uncensored on port 9082..."
  "$SERVER" \
    -m "$MODELS_DIR/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf" \
    -ngl 0 \
    --threads 8 \
    --threads-batch 16 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram 16384 \
    -crs 0.5 \
    --port 9082 \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

start_supergemma4() {
  echo "Starting SuperGemma4 26B Uncensored on port 9083..."
  "$SERVER" \
    -m "$MODELS_DIR/supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf" \
    -ngl 0 \
    --threads 8 \
    --threads-batch 16 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram 16384 \
    -crs 0.5 \
    --port 9083 \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

case "$MODE" in
  qwen36)      start_qwen36 ;;
  gemma4)      start_gemma4 ;;
  qwen36u)     start_qwen36u ;;
  supergemma4) start_supergemma4 ;;
  *) echo "Usage: $0 [qwen36|gemma4|qwen36u|supergemma4]" >&2; exit 1 ;;
esac

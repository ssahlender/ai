#!/usr/bin/env bash
# Starts llama-server on i9-13900 (Debian). Usage: ./start-i9.sh [qwen|gemma|both]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
SERVER="$IK_LLAMA_DIR/llama-server"
MODE="${1:-both}"

start_qwen() {
  echo "Starting Qwen3.6 on port 8080..."
  "$SERVER" \
    -m "$MODELS_DIR/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf" \
    -ngl 0 \
    --threads 8 \
    --threads-batch 16 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram 16384 \
    -crs 0.5 \
    --port 8080 \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

start_gemma() {
  echo "Starting Gemma4 on port 8081..."
  "$SERVER" \
    -m "$MODELS_DIR/gemma-4-26B-A4B-it-UD-Q5_K_M.gguf" \
    -ngl 0 \
    --threads 8 \
    --threads-batch 16 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram 16384 \
    -crs 0.5 \
    --port 8081 \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

case "$MODE" in
  qwen)  start_qwen ;;
  gemma) start_gemma ;;
  both)
    start_qwen &
    QWEN_PID=$!
    start_gemma &
    GEMMA_PID=$!
    trap "kill $QWEN_PID $GEMMA_PID 2>/dev/null" EXIT INT TERM
    wait
    ;;
  *) echo "Usage: $0 [qwen|gemma|both]" >&2; exit 1 ;;
esac

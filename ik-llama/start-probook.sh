#!/usr/bin/env bash
# Starts llama-server (Windows exe) from WSL2 on HP ProBook.
# Usage: ./start-probook.sh [qwen|gemma|both]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
SERVER="$IK_LLAMA_DIR/llama-server.exe"
MODE="${1:-both}"

# Windows exes need Windows-style paths for file arguments
win_path() { wslpath -w "$1"; }

start_qwen() {
  echo "Starting Qwen3.6 on port 8080..."
  "$SERVER" \
    -m "$(win_path "$MODELS_DIR/Qwen3.6-35B-A3B-UD-Q3_K_M.gguf")" \
    -ngl 0 \
    --threads 12 \
    --threads-batch 6 \
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
    -m "$(win_path "$MODELS_DIR/gemma-4-26B-A4B-it-UD-IQ4_NL.gguf")" \
    -ngl 0 \
    --threads 12 \
    --threads-batch 6 \
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

#!/usr/bin/env bash
# Starts llama-server (Windows exe) from WSL2 on HP ProBook.
# Usage: ./start-probook.sh [qwen|qwen36u|gemma]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
SERVER="$IK_LLAMA_DIR/llama-server.exe"
PORT=8080
MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "Usage: $0 [qwen|qwen36u|gemma]" >&2
  exit 1
fi

if pgrep -x llama-server.exe >/dev/null 2>&1; then
  echo "llama-server.exe is already running. Stop it first." >&2
  exit 1
fi

# Windows exes need Windows-style paths for file arguments
win_path() { wslpath -w "$1"; }

start_model() {
  local name="$1" model="$2" cram="${3:-16384}"
  echo "Starting $name on port $PORT..."
  "$SERVER" \
    -m "$(win_path "$MODELS_DIR/$model")" \
    -ngl 0 \
    --threads 12 \
    --threads-batch 6 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram "$cram" \
    -crs 0.5 \
    --port $PORT \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

case "$MODE" in
  qwen)    start_model "Qwen3.6 35B-A3B"            "Qwen3.6-35B-A3B-UD-Q3_K_M.gguf" ;;
  qwen36u) start_model "Qwen3.6 35B-A3B Uncensored" "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf" 8192 ;;
  gemma)   start_model "Gemma4 26B-A4B"             "gemma-4-26B-A4B-it-UD-IQ4_NL.gguf" ;;
  *) echo "Usage: $0 [qwen|qwen36u|gemma]" >&2; exit 1 ;;
esac

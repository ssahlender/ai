#!/usr/bin/env bash
# Starts llama-server (Windows exe) from WSL2 on HP ProBook.
# Usage: ./start-probook.sh [qwen|qwen36u|gemma]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
SERVER="$IK_LLAMA_DIR/llama-server.exe"
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

start_qwen36u() {
  echo "Starting Qwen3.6 35B-A3B Uncensored on port 8082..."
  "$SERVER" \
    -m "$(win_path "$MODELS_DIR/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf")" \
    -ngl 0 \
    --threads 12 \
    --threads-batch 6 \
    --ctx-size 32768 \
    -sps 0.5 \
    -cram 16384 \
    -crs 0.5 \
    --port 8082 \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v
}

case "$MODE" in
  qwen)    start_qwen ;;
  qwen36u) start_qwen36u ;;
  gemma)   start_gemma ;;
  *) echo "Usage: $0 [qwen|qwen36u|gemma]" >&2; exit 1 ;;
esac

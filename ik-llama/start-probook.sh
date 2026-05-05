#!/usr/bin/env bash
# Starts llama-server (Windows exe) from WSL2 on HP ProBook.
# Usage: ./start-probook.sh [qwen|qwen36u|gemma|qwen3coder]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
SERVER="$IK_LLAMA_DIR/llama-server.exe"
PORT=8080
MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "Usage: $0 [qwen|qwen36u|gemma|qwen3coder]" >&2
  exit 1
fi

if pgrep -x llama-server.exe >/dev/null 2>&1; then
  echo "llama-server.exe is already running. Stop it first." >&2
  exit 1
fi

# Windows exes need Windows-style paths for file arguments
win_path() { wslpath -w "$1"; }

start_model() {
  local name="$1" model="$2" ctx="${3:-32768}" cram="${4:-16384}"; shift 4
  echo "Starting $name on port $PORT (ctx=${ctx}, cram=${cram}MB)..."
  "$SERVER" \
    -m "$(win_path "$MODELS_DIR/$model")" \
    -ngl 0 \
    --threads 16 \
    --threads-batch 8 \
    --ctx-size "$ctx" \
    -sps 0.5 \
    -cram "$cram" \
    -crs 0.5 \
    -ctk q8_0 \
    -ctv q8_0 \
    -dt 0.1 \
    --port $PORT \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v \
    "$@"
}

# Qwen3 recommended YaRN params (beta-fast/slow from Qwen3 technical report)
YARN="--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1"
# Qwen3 recommended sampling params (thinking mode, from Qwen3 technical report)
SAMPLE="--temp 0.6 --top-p 0.95 --top-k 20"

#                                                                                              ctx    cram  extra
case "$MODE" in
  qwen)    start_model "Qwen3.6 35B-A3B"            "Qwen3.6-35B-A3B-UD-Q3_K_M.gguf"                              65536  16384 $YARN $SAMPLE ;;
  qwen36u) start_model "Qwen3.6 35B-A3B Uncensored" "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf" 32768   8192        $SAMPLE ;;
  gemma)   start_model "Gemma4 26B-A4B"             "gemma-4-26B-A4B-it-UD-IQ4_NL.gguf"                          65536  12288 ;;
  qwen3coder) start_model "Qwen3-Coder 30B-A3B"     "Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf"                   65536  16384 $YARN $SAMPLE ;;
  *) echo "Usage: $0 [qwen|qwen36u|gemma|qwen3coder]" >&2; exit 1 ;;
esac

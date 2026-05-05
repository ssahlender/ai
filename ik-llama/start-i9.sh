#!/usr/bin/env bash
# Starts llama-server on i9-13900 (Debian). Usage: ./start-i9.sh [qwen36|gemma4|qwen36u|supergemma4|qwen3coder|glm47flash]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
PORT=9080
MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "Usage: $0 [qwen36|gemma4|qwen36u|supergemma4|qwen3coder|glm47flash]" >&2
  exit 1
fi

if pgrep -x llama-server >/dev/null 2>&1; then
  echo "llama-server is already running. Stop it first." >&2
  exit 1
fi

start_model() {
  local name="$1" model="$2" ctx="${3:-32768}" cram="${4:-16384}"; shift 4
  echo "Starting $name on port $PORT (ctx=${ctx}, cram=${cram}MB)..."
  "$SERVER" \
    -m "$MODELS_DIR/$model" \
    -ngl 0 \
    --threads 16 \
    --threads-batch 20 \
    --ctx-size "$ctx" \
    -sps 0.5 \
    -cram "$cram" \
    -crs 0.5 \
    -ctk q8_0 \
    -ctv q8_0 \
    -dt 0.1 \
    --mlock \
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

#                                                                                             ctx     cram  extra
case "$MODE" in
  qwen36)      start_model "Qwen3.6 35B-A3B"            "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"                              65536  16384 $YARN $SAMPLE ;;
  gemma4)      start_model "Gemma4 26B-A4B"             "gemma-4-26B-A4B-it-UD-Q5_K_M.gguf"                           131072 32768 ;;
  qwen36u)     start_model "Qwen3.6 35B-A3B Uncensored" "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf"  65536  16384 $YARN $SAMPLE ;;
  supergemma4) start_model "SuperGemma4 26B Uncensored" "supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf"               131072 32768 ;;
  qwen3coder)  start_model "Qwen3-Coder 30B-A3B"        "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"                    65536  16384 $YARN $SAMPLE ;;
  glm47flash)  start_model "GLM-4.7-Flash 30B"          "zai-org_GLM-4.7-Flash-Q5_K_M.gguf"                           65536  16384        $SAMPLE --flash-attn off ;;
  *) echo "Usage: $0 [qwen36|gemma4|qwen36u|supergemma4|qwen3coder|glm47flash]" >&2; exit 1 ;;
esac

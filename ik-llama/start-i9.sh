#!/usr/bin/env bash
# Starts llama-server on i9-13900 (Debian). Usage: ./start-i9.sh [qwen3coderq5km|qwen36u27bq5kp|qwen36u35bq4kp|gemma4q5km|supergemma4q4km|glm47flashq5km]
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
PORT=9080
MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "Usage: $0 [qwen3coderq5km|qwen36u27bq5kp|qwen36u35bq4kp|gemma4q5km|supergemma4q4km|glm47flashq5km]" >&2
  exit 1
fi

normalize_mode() {
  case "$1" in
    qwen3coder:q5|qwen3coderq5|qwen3coderq5km) echo "qwen3coderq5km" ;;
    qwen36u27b|qwen36u27bq5kp) echo "qwen36u27bq5kp" ;;
    qwen36u35b|qwen36u35bq4kp) echo "qwen36u35bq4kp" ;;
    gemma4|gemma4q5km) echo "gemma4q5km" ;;
    supergemma4|supergemma4q4km) echo "supergemma4q4km" ;;
    glm47flash|glm47flashq5km) echo "glm47flashq5km" ;;
    *) return 1 ;;
  esac
}

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
    --threads "${IK_LLAMA_THREADS:-8}" \
    --threads-batch "${IK_LLAMA_THREADS_BATCH:-24}" \
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
YARN=(--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1)
# Qwen3 recommended sampling params (thinking mode, from Qwen3 technical report)
SAMPLE=(--temp 0.6 --top-p 0.95 --top-k 20)

#                                                                                             ctx     cram  extra
MODE="$(normalize_mode "$MODE" || true)"

case "$MODE" in
  qwen3coderq5km) start_model "Qwen3-Coder 30B-A3B Instruct Q5_K_M" "Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf"             65536  16384 "${YARN[@]}" "${SAMPLE[@]}" ;;
  qwen36u27bq5kp) start_model "Qwen3.6 27B Uncensored Q5_K_P" "Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf"    65536  24576 "${YARN[@]}" "${SAMPLE[@]}" ;;
  qwen36u35bq4kp) start_model "Qwen3.6 35B-A3B Uncensored Q4_K_P" "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf" 65536  16384 "${YARN[@]}" "${SAMPLE[@]}" ;;
  gemma4q5km)     start_model "Gemma4 26B-A4B Q5_K_M"     "gemma-4-26B-A4B-it-UD-Q5_K_M.gguf"                           131072 32768 ;;
  supergemma4q4km) start_model "SuperGemma4 26B Uncensored Q4_K_M" "supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf"       131072 32768 ;;
  glm47flashq5km) start_model "GLM-4.7-Flash 30B Q5_K_M"   "zai-org_GLM-4.7-Flash-Q5_K_M.gguf"                           65536  16384        "${SAMPLE[@]}" ;;
  *) echo "Usage: $0 [qwen3coderq5km|qwen36u27bq5kp|qwen36u35bq4kp|gemma4q5km|supergemma4q4km|glm47flashq5km]" >&2; exit 1 ;;
esac

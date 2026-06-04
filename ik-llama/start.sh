#!/usr/bin/env bash
# Starts llama-server. Usage: ./start.sh <machine> <mode>
#   Machine: i9 | probook | macbook-air
#   Mode:    machine-specific model shortname (see usage)
set -euo pipefail

MACHINE="${1:-}"
MODE="${2:-}"

# ── machine config ─────────────────────────────────────────────────
case "$MACHINE" in
  i9)
    IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
    SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
    MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
    PORT="${IK_LLAMA_PORT:-9080}"
    NGL=0; THREADS="${IK_LLAMA_THREADS:-8}"; THREADS_BATCH="${IK_LLAMA_THREADS_BATCH:-24}"
    MLOCK="--mlock"
    PGREP_NAME="llama-server"
    WSL_PATH=
    SAMPLE_BASE=(--temp "${IK_LLAMA_TEMP:-0.2}" --top-p "${IK_LLAMA_TOP_P:-0.8}" --top-k "${IK_LLAMA_TOP_K:-20}")
    YARN=(--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1)
    MODES=(
      "qwen36u27bq5kp|Qwen3.6 27B Uncensored Q5_K_P|Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf|65536|24576|YARN|SAMPLE|mmproj-Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-f16.gguf"
      "qwen36u35bq6kp|Qwen3.6 35B-A3B Uncensored Q6_K_P|Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P.gguf|131072|24576|YARN|SAMPLE|mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf"
      "qwopus35bq5km|Qwopus3.6 35B-A3B Q5_K_M|Qwopus3.6-35B-A3B-v1-Q5_K_M.gguf|131072|24576|YARN|SAMPLE|mmproj-F32.gguf"
      "qwopus35bq6k|Qwopus3.6 35B-A3B Q6_K|Qwopus3.6-35B-A3B-v1-Q6_K.gguf|131072|24576|YARN|SAMPLE|mmproj-F32.gguf"
      "gemma4q5km|Gemma4 26B-A4B Q5_K_M|gemma-4-26B-A4B-it-UD-Q5_K_M.gguf|131072|32768|||mmproj-F16.gguf"
      "supergemma4q4km|SuperGemma4 26B Uncensored Q4_K_M|supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf|131072|32768"
      "glm47flashq5km|GLM-4.7-Flash 30B Q5_K_M|zai-org_GLM-4.7-Flash-Q5_K_M.gguf|65536|16384|NOSAMPLE||"
    )
    ;;
  probook)
    IK_LLAMA_DIR="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
    SERVER="$IK_LLAMA_DIR/llama-server.exe"
    MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
    PORT="${IK_LLAMA_PORT:-8080}"
    NGL=0; THREADS=16; THREADS_BATCH=8
    MLOCK=
    PGREP_NAME="llama-server.exe"
    WSL_PATH=1
    SAMPLE_BASE=(--temp 0.6 --top-p 0.95 --top-k 20)
    YARN=(--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1)
    MODES=(
      "qwen36u35b|Qwen3.6 35B-A3B Uncensored|Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf|32768|8192|NOSAMPLE|"
      "gemma|Gemma4 26B-A4B|gemma-4-26B-A4B-it-UD-IQ4_NL.gguf|65536|12288"
      "qwen3coder|Qwen3-Coder 30B-A3B|Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf|65536|16384|YARN|SAMPLE"
      "glm47flash|GLM-4.7-Flash 30B|zai-org_GLM-4.7-Flash-Q4_K_M.gguf|32768|8192|NOSAMPLE|"
    )
    ;;
  macbook-air)
    SERVER="${IK_LLAMA_SERVER:-}"
    [ -z "$SERVER" ] && SERVER="$(command -v llama-server 2>/dev/null || echo '')"
    if [ -z "$SERVER" ]; then
      if [ -n "${IK_LLAMA_DIR:-}" ] && [ -x "$IK_LLAMA_DIR/build/bin/llama-server" ]; then
        SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
      fi
    fi
    [ -n "$SERVER" ] || { echo "llama-server not found. Install: brew install llama.cpp" >&2; exit 1; }
    MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
    PORT="${IK_LLAMA_PORT:-9080}"
    NGL=99; THREADS="${IK_LLAMA_THREADS:-4}"; THREADS_BATCH="${IK_LLAMA_THREADS:-4}"
    MLOCK="--mlock"
    PGREP_NAME="llama-server"
    WSL_PATH=
    SAMPLE_BASE=()
    YARN=(--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1)
    MODES=(
      "qwen36u27b|Qwen3.6 27B IQ4_XS|Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ4_XS.gguf|32768|8192|YARN||mmproj-Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-f16.gguf"
      "qwen36u35b|Qwen3.6 35B-A3B IQ4_NL|Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf|16384|4096|YARN||mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf"
    )
    ;;
  *) echo "Usage: $0 <i9|probook|macbook-air> <mode>" >&2; exit 1 ;;
esac

# ── validate ───────────────────────────────────────────────────────
if [ -z "$MODE" ]; then
  echo "Usage: $0 $MACHINE <mode>" >&2
  echo "Modes:" >&2
  for m in "${MODES[@]}"; do
    printf "  %-22s %s\n" "${m%%|*}" "$(echo "$m" | cut -d'|' -f2)"
  done
  exit 1
fi

if [ -n "$PGREP_NAME" ] && pgrep -x "$PGREP_NAME" >/dev/null 2>&1; then
  echo "$PGREP_NAME is already running. Stop it first." >&2
  exit 1
fi

# ── path helper ────────────────────────────────────────────────────
model_path() {
  if [ -n "$WSL_PATH" ] && command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$MODELS_DIR/$1"
  else
    echo "$MODELS_DIR/$1"
  fi
}

# ── start_model ────────────────────────────────────────────────────
start_model() {
  local name="$1" model="$2" ctx="${3:-32768}" cram="${4:-16384}"; shift 4
  ctx="${IK_LLAMA_CTX_SIZE:-$ctx}"
  cram="${IK_LLAMA_CRAM_MB:-$cram}"
  local extra=("$@")
  echo "Starting $name on port $PORT (ctx=${ctx}, cram=${cram}MB, threads=${THREADS}/${THREADS_BATCH})..."
  exec "$SERVER" \
    -m "$(model_path "$model")" \
    -ngl "$NGL" \
    --threads "$THREADS" \
    --threads-batch "$THREADS_BATCH" \
    --ctx-size "$ctx" \
    -sps 0.5 \
    -cram "$cram" \
    -crs 0.5 \
    -ctk q8_0 \
    -ctv q8_0 \
    -dt 0.1 \
    ${MLOCK:-} \
    --port "$PORT" \
    --host 0.0.0.0 \
    --jinja \
    -rea off \
    -v \
    "${extra[@]}"
}

# ── resolve mode ───────────────────────────────────────────────────
FOUND=
for m in "${MODES[@]}"; do
  IFS='|' read -r SN NAME FILE CTX CRAM YF SF MMPROJ <<< "$m"
  if [ "$SN" = "$MODE" ]; then
    FOUND=1
    EXTRA=()
    [ "$YF" = "YARN" ] && EXTRA+=("${YARN[@]}")
    if [ "$SF" = "SAMPLE" ]; then
      EXTRA+=("${SAMPLE_BASE[@]}")
    elif [ "$SF" != "NOSAMPLE" ]; then
      EXTRA+=("${SAMPLE_BASE[@]}")
    fi
    [ -n "$MMPROJ" ] && EXTRA+=(--mmproj "$(model_path "$MMPROJ")")
    start_model "$NAME" "$FILE" "$CTX" "$CRAM" "${EXTRA[@]}"
  fi
done

[ -n "$FOUND" ] || { echo "Unknown mode: $MODE" >&2; exit 1; }

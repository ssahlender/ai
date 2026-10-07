#!/usr/bin/env bash
# Starts llama-server. Usage: ./start.sh <machine> <mode>
# IK_LLAMA_EXTRA_ARGS appends raw llama-server flags last (later flags win), e.g. '--slot-save-path DIR' or '-rea on'.
#   Machine: i9 | macbook-air
#   Mode:    GGUF file name without .gguf, or its number from the list
#            (run without a mode for an interactive numbered menu)
#   (ProBook runs natively on Windows via llm\start-llm.ps1)
set -euo pipefail

MACHINE="${1:-}"
MODE="${2:-}"

# ── host reality (2026-09-27) ──────────────────────────────────────
# Checked before the per-host config: the branches below bail out on their own terms (a missing
# llama-server) and that would hide the real reason these two hosts changed.
if [ "$MACHINE" = "probook" ]; then
  echo "WSL is retired and the ProBook now runs the engine natively on Windows:" >&2
  echo "use  llm\\start-llm.ps1 <mode>  instead (or ..\\llm\\start-llm.ps1 from ik-llama). See llm/README.md." >&2
  exit 1
elif [ "$MACHINE" = "macbook-air" ]; then
  _gguf_dir="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
  if ! compgen -G "$_gguf_dir/*.gguf" >/dev/null 2>&1; then
    echo "No GGUF in $_gguf_dir: this Mac's models belong to Ollama (qwen36-35b-a3b = UD-Q2_K_XL)." >&2
    echo "Use ollama/start.sh instead (see ollama/README.md). To use this GGUF path, fetch first:" >&2
    echo "  ./download-models.sh macbook-air" >&2
    exit 1
  fi
fi


# ── machine config ─────────────────────────────────────────────────
case "$MACHINE" in
  i9)
    IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
    SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
    MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
    PORT="${IK_LLAMA_PORT:-9080}"
    NGL=0; THREADS="${IK_LLAMA_THREADS:-8}"; THREADS_BATCH="${IK_LLAMA_THREADS_BATCH:-24}"
    UBATCH="${IK_LLAMA_UBATCH:-1024}"
    MLOCK="--mlock"
    PGREP_NAME="llama-server"
    SAMPLE_BASE=(--temp "${IK_LLAMA_TEMP:-0.2}" --top-p "${IK_LLAMA_TOP_P:-0.8}" --top-k "${IK_LLAMA_TOP_K:-20}")
    YARN=(--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1)
    MODES=(
      "Qwen3.6 35B-A3B Uncensored Q6_K_P|Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P.gguf|131072|24576||SAMPLE|mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf"
      "Qwen3.6 35B-A3B MTP UD-Q6_K (speculative, ~+25% tg on code)|Qwen3.6-35B-A3B-MTP-UD-Q6_K.gguf|131072|24576||SAMPLE||mtp:n_max=1,p_min=0.0"
    )
    ;;
  macbook-air)
    SERVER="${IK_LLAMA_SERVER:-}"
    [ -z "$SERVER" ] && SERVER="$(command -v llama-server 2>/dev/null || echo '')"
        # Non-interactive shells (ssh, launchd) do not inherit Homebrew's PATH, so
        # `command -v` alone fails even though llama.cpp is installed. Probe the standard
        # prefixes before giving up.
        if [ -z "$SERVER" ]; then
          for c in /opt/homebrew/bin/llama-server /usr/local/bin/llama-server "$HOME/.local/bin/llama-server"; do
            [ -x "$c" ] && { SERVER="$c"; break; }
          done
        fi
    if [ -z "$SERVER" ]; then
      if [ -n "${IK_LLAMA_DIR:-}" ] && [ -x "$IK_LLAMA_DIR/build/bin/llama-server" ]; then
        SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
      fi
    fi
    [ -n "$SERVER" ] || { echo "llama-server not found. Install: brew install llama.cpp" >&2; exit 1; }
    MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
    PORT="${IK_LLAMA_PORT:-9080}"
    NGL=99; THREADS="${IK_LLAMA_THREADS:-4}"; THREADS_BATCH="${IK_LLAMA_THREADS_BATCH:-4}"
    MLOCK="--mlock"
    PGREP_NAME="llama-server"
    SAMPLE_BASE=()
    YARN=(--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1)
    MODES=(
      "Qwen3.6 27B IQ4_XS|Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ4_XS.gguf|32768|8192|||mmproj-Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-f16.gguf"
      "Qwen3.6 35B-A3B IQ4_NL|Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf|16384|4096|||mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf"
      "Qwen3-Coder 30B-A3B IQ4_NL|Qwen3-Coder-30B-A3B-Instruct-IQ4_NL.gguf|32768|8192"
    )
    ;;
  *) echo "Usage: $0 <i9|macbook-air> <mode>" >&2; exit 1 ;;
esac


# Keep one full-context slot by default. Multiple unrelated agent sessions on
# one slot pool invalidate each other's prompt cache and divide the context.
PARALLEL="${IK_LLAMA_PARALLEL:-1}"

# ── validate ───────────────────────────────────────────────────────
list_modes() {
  local i=1 m _desc _file
  for m in "${MODES[@]}"; do
    IFS='|' read -r _desc _file _ <<< "$m"
    printf "  %2d) %s\n      %s\n" "$i" "${_file%.gguf}" "$_desc"
    i=$((i + 1))
  done
}

if [ -z "$MODE" ]; then
  if [ -t 0 ] && [ -t 1 ]; then
    echo "Models for $MACHINE:"
    list_modes
    read -r -p "Select a number: " MODE
  else
    echo "Usage: $0 $MACHINE <mode|number>" >&2
    echo "Modes:" >&2
    list_modes >&2
    exit 1
  fi
fi

# A number picks the Nth entry of the list above.
if [[ "$MODE" =~ ^[0-9]+$ ]]; then
  if [ "$MODE" -lt 1 ] || [ "$MODE" -gt "${#MODES[@]}" ]; then
    echo "No model number $MODE (valid: 1-${#MODES[@]})." >&2
    exit 1
  fi
  IFS='|' read -r _desc _file _ <<< "${MODES[$((MODE - 1))]}"
  MODE="${_file%.gguf}"
  echo "Selected: $MODE"
fi

if [ -n "$PGREP_NAME" ] && pgrep -x "$PGREP_NAME" >/dev/null 2>&1; then
  echo "$PGREP_NAME is already running. Stop it first." >&2
  exit 1
fi

# ── path helper ────────────────────────────────────────────────────
model_path() {
  echo "$MODELS_DIR/$1"
}

# ── start_model ────────────────────────────────────────────────────
start_model() {
  local name="$1" model="$2" ctx="${3:-32768}" cram="${4:-16384}"; shift 4
  ctx="${IK_LLAMA_CTX_SIZE:-$ctx}"
  cram="${IK_LLAMA_CRAM_MB:-$cram}"
  local extra=("$@")
  echo "Starting $name on port $PORT (ctx=${ctx}, cram=${cram}MB, threads=${THREADS}/${THREADS_BATCH}, ubatch=${UBATCH:-default}, parallel=${PARALLEL})..."
  exec "$SERVER" \
    -m "$(model_path "$model")" \
    -ngl "$NGL" \
    --threads "$THREADS" \
    --threads-batch "$THREADS_BATCH" \
    ${UBATCH:+--ubatch-size "$UBATCH"} \
    --parallel "$PARALLEL" \
    --ctx-size "$ctx" \
    -sps 0.5 \
    -cram "$cram" \
    -crs 0.5 \
    -ctk q8_0 \
    -ctv q8_0 \
    -dt 0.1 \
    ${MLOCK:-} \
    --port "$PORT" \
    --host "${IK_LLAMA_BIND:-${IK_LLAMA_HOST:-127.0.0.1}}" \
    --jinja \
    --context-shift on \
    -rea off \
    -v \
    ${extra[@]+"${extra[@]}"} \
    ${IK_LLAMA_EXTRA_ARGS:-}
}

# ── resolve mode ───────────────────────────────────────────────────
FOUND=
for m in "${MODES[@]}"; do
  IFS='|' read -r NAME FILE CTX CRAM YF SF MMPROJ SPEC <<< "$m"
  if [ "${FILE%.gguf}" = "$MODE" ]; then
    FOUND=1
    EXTRA=()
    [ "$YF" = "YARN" ] && EXTRA+=("${YARN[@]}")
    if [ "$SF" = "SAMPLE" ]; then
      EXTRA+=(${SAMPLE_BASE[@]+"${SAMPLE_BASE[@]}"})
    fi
    [ -n "$MMPROJ" ] && EXTRA+=(--mmproj "$(model_path "$MMPROJ")")
    [ -n "${SPEC:-}" ] && EXTRA+=(--spec-type "$SPEC")
    case "$FILE" in
      *Uncensored-HauhauCS*)
        EXTRA+=(--chat-template-file "$(dirname "$(realpath "$0")")/qwen3-template.j2")
        ;;
    esac
    start_model "$NAME" "$FILE" "$CTX" "$CRAM" ${EXTRA[@]+"${EXTRA[@]}"}
  fi
done

[ -n "$FOUND" ] || { echo "Unknown mode: $MODE" >&2; exit 1; }

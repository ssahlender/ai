#!/usr/bin/env bash
# Starts llama-server. Usage: ./start.sh [i9] <mode>
# IK_LLAMA_SPEC overrides the mode's --spec-type flags (raw; 'none' disables).
# IK_LLAMA_EXTRA_ARGS appends raw llama-server flags last (later flags win), e.g. '--slot-save-path DIR' or '-rea on'.
#   Machine: i9 (the ProBook and the Mac have their own folders: llm/probook, llm/mac)
#   Mode:    GGUF file name without .gguf, or its number from the list
#            (run without a mode for an interactive numbered menu)
set -euo pipefail

# `i9` is the only machine these scripts serve: the argument is optional (still accepted).
case "${1:-}" in i9|probook|macbook-air|mac) ;; *) set -- i9 "$@" ;; esac

MACHINE="${1:-}"
MODE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "$SCRIPT_DIR/../shared" && pwd)"

# ── load_modes: one source of truth (models.json via models.py) for every script ──
# Renders each machine's model list in the same pipe-delimited shape MODES always used
# internally, so the resolve-mode loop below didn't need to change: only where the data
# comes from did. models.py also owns the models.local.json/IK_LLAMA_MODELS_JSON
# resolution, instead of every script re-deriving it.
load_modes() {
  python3 "$SHARED_DIR/models.py" modes "$1"
}

# Other machines have their own folder (llm/README.md): say so instead of a bare usage error.
case "$MACHINE" in
  probook)     echo "The ProBook runs natively on Windows: llm\\probook\\start-llm.ps1 <mode>" >&2; exit 1 ;;
  macbook-air|mac) echo "The Mac runs Ollama: llm/llama-swap-setup.sh" >&2; exit 1 ;;
esac

# ── machine config ─────────────────────────────────────────────────
case "$MACHINE" in
  i9)
    IK_LLAMA_DIR="${IK_LLAMA_DIR:-$HOME/.local/share/llama.cpp/ik_llama}"
    SERVER="$IK_LLAMA_DIR/build/bin/llama-server"
    MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
    PORT="${IK_LLAMA_PORT:-9080}"
    NGL=0; THREADS="${IK_LLAMA_THREADS:-8}"; THREADS_BATCH="${IK_LLAMA_THREADS_BATCH:-24}"
    UBATCH="${IK_LLAMA_UBATCH:-1024}"
    MLOCK="--mlock"
    PGREP_NAME="llama-server"
    SAMPLE_BASE=(--temp "${IK_LLAMA_TEMP:-0.2}" --top-p "${IK_LLAMA_TOP_P:-0.8}" --top-k "${IK_LLAMA_TOP_K:-20}")
    YARN=(--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1)
    # Widens how many tokens before an exact-prefix match a context checkpoint still gets reused
    # (default 5 is stingy for an agent harness's small per-turn edits). ik_llama.cpp-specific
    # flag, verified present in this build's --help.
    # brew's mainline llama.cpp instead and has not been checked for it.
    CTX_CKPT=(-ctx-ckpt-t "${IK_LLAMA_CTX_CKPT_T:-64}")
    ;;
  *) echo "Usage: $0 i9 <mode>" >&2; exit 1 ;;
esac

mapfile -t MODES < <(load_modes "$MACHINE")
if [ "${#MODES[@]}" -eq 0 ]; then
  echo "No models for '$MACHINE' in $(python3 "$SHARED_DIR/models.py" path)." >&2
  exit 1
fi


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

# IK_LLAMA_PRINT_CMD=1 is how llama-swap drives this script: it wants the fully-built
# llama-server argv for one mode, not an actual exec here. llama-swap itself serializes
# model switching (stops the old backend before starting the new one), so the
# already-running guard and the proxy-ensure step below (both meant for ad-hoc manual
# starts) don't apply to that path.
PRINT_CMD="${IK_LLAMA_PRINT_CMD:-0}"

if [ "$PRINT_CMD" != 1 ] && [ -n "$PGREP_NAME" ] && pgrep -x "$PGREP_NAME" >/dev/null 2>&1; then
  echo "$PGREP_NAME is already running. Stop it first." >&2
  exit 1
fi

# ── path helper ────────────────────────────────────────────────────
model_path() {
  echo "$MODELS_DIR/$1"
}

# ── local-proxy (keep-alive for cold prefill) ─────────────────────
# OpenCode/Pi talk to llama-server directly on $PORT by default, with no
# idle-read keep-alive. Cold prefill on CPU can run minutes with zero bytes
# from upstream, which trips the client's own idle-read timeout ("Timed out
# waiting for response headers") well before the request actually fails.
# local-proxy.py (same one claude-providers.sh uses) sends SSE keep-alives
# during those gaps, so start it here too and leave it running for any agent
# wired to port 9081 instead of $PORT.
ensure_local_proxy() {
  local expected="ok upstream=127.0.0.1:${PORT} max_tokens_cap="
  local health_out
  health_out=$(curl -sf --max-time 2 "http://localhost:9081/proxy-health" 2>/dev/null || true)
  case "$health_out" in
    "${expected}"*) return 0 ;;
  esac
  LOCAL_PROXY_UPSTREAM="http://127.0.0.1:${PORT}" \
  LOCAL_PROXY_PORT=9081 \
    nohup python3 "$SHARED_DIR/local-proxy.py" >/tmp/local-proxy.log 2>&1 &
  disown
  local i
  for i in {1..10}; do
    sleep 0.3
    health_out=$(curl -sf --max-time 1 "http://localhost:9081/proxy-health" 2>/dev/null || true)
    case "$health_out" in
      "${expected}"*) echo "Started local-proxy on port 9081 (upstream 127.0.0.1:${PORT})."; return 0 ;;
    esac
  done
  echo "Warning: local-proxy did not come up; agents pointed at 9081 won't work. Check /tmp/local-proxy.log" >&2
}

# ── build_argv: the one place the server command is built ──────────
# Used by both paths below, so a flag cannot change in one and not the other:
#   IK_LLAMA_PRINT_CMD=1  prints it shell-quoted on one line, for llama-swap's
#                         cmd: bash -c 'eval "$(IK_LLAMA_PRINT_CMD=1 ... start.sh i9 <mode>)"'  (see shared/llama_swap_config.py)
#   otherwise             execs it (a bare server on $PORT, plus local-proxy on 9081)
build_argv() {
  local model="$1" ctx="$2" cram="$3"; shift 3
  local extra=("$@")
  ARGV=(
    "$SERVER"
    -m "$(model_path "$model")"
    -ngl "$NGL"
    --threads "$THREADS"
    --threads-batch "$THREADS_BATCH"
    ${UBATCH:+--ubatch-size "$UBATCH"}
    --parallel "$PARALLEL"
    --ctx-size "$ctx"
    -sps 0.5
    -cram "$cram"
    -crs 0.5
    -ctk q8_0
    -ctv q8_0
    -dt 0.1
    ${CTX_CKPT[@]+"${CTX_CKPT[@]}"}
    ${MLOCK:-}
    --port "$PORT"
    --host "${IK_LLAMA_BIND:-${IK_LLAMA_HOST:-127.0.0.1}}"
    --jinja
    --context-shift on
    -rea off
    -v
    ${extra[@]+"${extra[@]}"}
    ${IK_LLAMA_EXTRA_ARGS:-}
  )
}

# ── start_model ────────────────────────────────────────────────────
start_model() {
  local name="$1" model="$2" ctx="${3:-32768}" cram="${4:-16384}"; shift 4
  ctx="${IK_LLAMA_CTX_SIZE:-$ctx}"
  cram="${IK_LLAMA_CRAM_MB:-$cram}"
  build_argv "$model" "$ctx" "$cram" "$@"
  if [ "$PRINT_CMD" = 1 ]; then
    printf 'exec'
    printf ' %q' "${ARGV[@]}"
    printf '\n'
    return 0
  fi
  ensure_local_proxy
  echo "Starting $name on port $PORT (ctx=${ctx}, cram=${cram}MB, threads=${THREADS}/${THREADS_BATCH}, ubatch=${UBATCH:-default}, parallel=${PARALLEL})..."
  exec "${ARGV[@]}"
}

# ── resolve mode ───────────────────────────────────────────────────
FOUND=
for m in "${MODES[@]}"; do
  IFS='|' read -r NAME FILE CTX CRAM YF SF MMPROJ SPEC CT <<< "$m"
  if [ "${FILE%.gguf}" = "$MODE" ]; then
    FOUND=1
    EXTRA=()
    [ "$YF" = "YARN" ] && EXTRA+=("${YARN[@]}")
    if [ "$SF" = "SAMPLE" ]; then
      EXTRA+=(${SAMPLE_BASE[@]+"${SAMPLE_BASE[@]}"})
    fi
    # The server disables speculative decoding while a vision projector is loaded; IK_LLAMA_NO_MMPROJ=1 trades vision for drafting.
    [ -n "$MMPROJ" ] && [ -z "${IK_LLAMA_NO_MMPROJ:-}" ] && EXTRA+=(--mmproj "$(model_path "$MMPROJ")")
    # IK_LLAMA_SPEC replaces the mode's speculative setup with raw flags (e.g. two-stage chains, where the
    # self-spec stage must come before mtp); IK_LLAMA_SPEC=none turns speculation off.
    if [ -n "${IK_LLAMA_SPEC:-}" ]; then
      [ "$IK_LLAMA_SPEC" = none ] || EXTRA+=(${IK_LLAMA_SPEC})
    elif [ -n "${SPEC:-}" ]; then
      EXTRA+=(${SPEC})
    fi
    [ "$CT" = "CT" ] && EXTRA+=(--chat-template-file "$SHARED_DIR/qwen3-template.j2")
    start_model "$NAME" "$FILE" "$CTX" "$CRAM" ${EXTRA[@]+"${EXTRA[@]}"}
  fi
done

[ -n "$FOUND" ] || { echo "Unknown mode: $MODE" >&2; exit 1; }

#!/usr/bin/env bash
# claude-providers.sh — Claude Code provider/model picker
#   Interactive:  ./claude-providers.sh [-c] [-r <session-id>]
#   Direct:       ./claude-providers.sh <provider> [model] [-c] [-r <session-id>]
#
# Providers:
#   local          Local ik_llama.cpp server (auto-detects port)
#   openrouter     OpenRouter proxy (200+ models, Anthropic format)
#   nvidia         NVIDIA NIM free models via local proxy (Anthropic→OpenAI bridge)
#   nvidia-proxy   Same as nvidia, explicit
#   opencode-go    OpenCode Go subscription (MiniMax/Qwen only, Anthropic format)
#   opencode-proxy OpenCode Go OpenAI-only models via local proxy (DeepSeek/Kimi/GLM)
#
# Session flags (work in both picker and direct mode):
#   -c / --continue          Continue the most recent conversation
#   -r / --resume <id>       Resume a specific session by ID
#
# Sources ~/.secrets for API keys (OPENROUTER_API_KEY, NVIDIA_API_KEY, OPENCODE_GO_API_KEY).
set -euo pipefail

SECRETS="$HOME/.secrets"
[ -f "$SECRETS" ] && . "$SECRETS"

# Pre-parse session-continuation flags — forwarded to claude in all modes.
# Must happen before routing to picker/direct so -c works without a provider arg.
CONTINUE_FLAG=()
_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--continue)
      CONTINUE_FLAG+=(-c)
      shift
      ;;
    -r|--resume)
      [[ $# -ge 2 ]] || { echo "Usage: -r <session-id>" >&2; exit 1; }
      CONTINUE_FLAG+=(-r "$2")
      shift 2
      ;;
    *)
      _args+=("$1")
      shift
      ;;
  esac
done
set -- "${_args[@]+"${_args[@]}"}"
unset _args

# ── helpers ──────────────────────────────────────────────────────────

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

launch() {
  local base_url="$1" api_key="$2" sonnet="$3" haiku="$4" label="$5"
  local tip_provider="${label%%:*}" tip_model="${label#*:}"
  shift 5  # consume our 5 args — leftover $@ goes to claude
  # Set CLAUDE_PROVIDERS_NO_BARE=1 if you logged out of claude.ai first
  # and want full hooks/CLAUDE.md.
  local bare_flag="--bare"
  if [ "${CLAUDE_PROVIDERS_NO_BARE:-}" = "1" ]; then
    bare_flag=""
    # warn if still signed in (will hijack the request to claude.ai)
    if [ -f "$HOME/.claude/.credentials.json" ] && grep -q '"claudeAiOauth"' "$HOME/.claude/.credentials.json" 2>/dev/null; then
      red "claude.ai login detected — requests may route to claude.ai instead of $base_url."
      red "Either:  claude /logout   or   remove CLAUDE_PROVIDERS_NO_BARE=1"
      exit 1
    fi
  fi

  echo
  bold "Launching Claude Code: $label"
  dim "  SONNET = $sonnet"
  dim "  HAIKU  = $haiku"
  dim "  URL    = $base_url"
  echo
  dim "Tip: skip the picker next time with:"
  dim "  ./claude-providers.sh $tip_provider $tip_model"
  echo
  # shellcheck disable=SC2086
  ANTHROPIC_BASE_URL="$base_url" \
  ANTHROPIC_API_KEY="$api_key" \
  ANTHROPIC_CUSTOM_MODEL_OPTION="$sonnet" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku" \
  ANTHROPIC_TIMEOUT="${ANTHROPIC_TIMEOUT:-1800000}" \
  exec claude $bare_flag --model "$sonnet" "${CONTINUE_FLAG[@]+"${CONTINUE_FLAG[@]}"}" "$@"
}

# ── local model detection ────────────────────────────────────────────

detect_local() {
  local model host
  # WSL2: server runs on Windows host, reachable via default gateway IP
  # Native: server runs on localhost
  if is_wsl; then
    host=$(ip route show default | awk '{print $3; exit}')
    [ -n "$host" ] || host="127.0.0.1"
  else
    host="127.0.0.1"
  fi
  model=$(curl -sf --max-time 3 --connect-timeout 2 "http://${host}:9080/v1/models" 2>/dev/null | \
          python3 -c "
import sys, json, os
d = json.load(sys.stdin)
full = d['data'][0]['id']
# strip path prefix and .gguf suffix to get the model stem
name = os.path.basename(full)
if name.endswith('.gguf'):
    name = name[:-5]
print(name)
" 2>/dev/null || true)
  if [ -n "$model" ]; then
    echo "$model"
    return
  fi
  echo ""
}

detect_local_ctx() {
  local host
  if is_wsl; then
    host=$(ip route show default | awk '{print $3; exit}')
    [ -n "$host" ] || host="127.0.0.1"
  else
    host="127.0.0.1"
  fi
  curl -sf --max-time 3 --connect-timeout 2 "http://${host}:9080/props" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('default_generation_settings', {}).get('n_ctx', ''))
" 2>/dev/null || true
}

llama_host() {
  if is_wsl; then
    ip route show default | awk '{print $3; exit}'
  else
    echo "127.0.0.1"
  fi
}

# ── openrouter models ─────────────────────────────────────────────────

OR_MODELS=(
  "openrouter/free:Free Router (auto-picks free model)"
  "google/gemini-2.5-pro:Gemini 2.5 Pro"
  "deepseek/deepseek-v4-pro:DeepSeek V4 Pro"
  "qwen/qwen3.6-plus:Qwen3.6 Plus"
  "moonshotai/kimi-k2.6:Kimi K2.6"
  "moonshotai/kimi-k2.6:free:Kimi K2.6 (free)"
  "nvidia/nemotron-3-ultra-550b-a55b:free:Nemotron 3 Ultra 550B (free)"
  "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free:Nemotron 3 Nano Omni (free)"
  "anthropic/claude-sonnet-4:Claude Sonnet 4"
  "anthropic/claude-opus-4:Claude Opus 4"
  "openrouter/owl-alpha:OWL Alpha"
)

# ── nvidia models (NVIDIA NIM — Anthropic format may not work) ──────

NV_MODELS=(
  "nvidia/nemotron-3-super-120b-a12b:Nemotron 3 Super 120B"
  "nvidia/llama-4-maverick:Llama-4 Maverick"
  "nvidia/nemotron-3-ultra-550b-a55b:Nemotron 3 Ultra 550B"
)

# ── opencode-go models (Anthropic Messages API only) ─────────────────

OCG_MODELS=(
  "qwen3.7-max:Qwen3.7 Max"
  "qwen3.7-plus:Qwen3.7 Plus"
  "qwen3.6-plus:Qwen3.6 Plus"
  "minimax-m3:MiniMax M3"
  "minimax-m2.7:MiniMax M2.7"
  "minimax-m2.5:MiniMax M2.5"
)

# ── opencode-proxy models (routes through ocg-proxy.py, port 4099) ──

OCG_PROXY_MODELS=(
  "deepseek-v4-pro:DeepSeek V4 Pro"
  "kimi-k2.6:Kimi K2.6"
  "glm-4.7:GLM-4.7"
)

# ── nvidia-proxy models (routes through ocg-proxy.py, port 4098) ─────

NV_PROXY_MODELS=(
  "nvidia/nemotron-3-ultra-550b-a55b:Nemotron 3 Ultra 550B"
  "nvidia/nemotron-3-super-120b-a12b:Nemotron 3 Super 120B"
  "nvidia/nemotron-3-nano-30b-a3b:Nemotron 3 Nano 30B"
  "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:Nemotron 3 Nano Omni Reasoning"
  "nvidia/nemotron-nano-9b-v2:Nemotron Nano 9B V2"
  "nvidia/llama-3.3-nemotron-super-49b-v1:Llama 3.3 Nemotron Super 49B"
  "nvidia/llama-3.1-nemotron-ultra-253b-v1:Llama 3.1 Nemotron Ultra 253B"
)

# ── proxy start (generic, param: port upstream_url api_key label) ─────

start_proxy() {
  local port="$1" upstream_url="$2" api_key="$3" label="$4" logfile="$5" models="$6"
  if curl -sf --max-time 2 "http://localhost:${port}/health" >/dev/null 2>&1; then
    return 0
  fi
  fuser -k "${port}/tcp" 2>/dev/null || true
  sleep 0.5
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  OCG_PROXY_PORT="$port" \
  OCG_PROXY_UPSTREAM_URL="$upstream_url" \
  OCG_PROXY_API_KEY="$api_key" \
  OCG_PROXY_MODELS="$models" \
    SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}" \
    REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}" \
    python3 "$script_dir/ocg-proxy.py" >"$logfile" 2>&1 &
  for i in {1..10}; do
    sleep 0.5
    if curl -sf --max-time 2 "http://localhost:${port}/health" >/dev/null 2>&1; then
      echo "Started ${label} proxy on port ${port}"
      return 0
    fi
  done
  red "Failed to start proxy. Check ${logfile}"
  exit 1
}

start_ocg_proxy() {
  start_proxy 4099 "https://opencode.ai/zen/go/v1" "${OPENCODE_GO_API_KEY:-}" "ocg" "/tmp/ocg-proxy.log" \
    "deepseek-v4-pro,kimi-k2.6,glm-4.7"
}

start_nv_proxy() {
  start_proxy 4098 "https://integrate.api.nvidia.com/v1" "${NVIDIA_API_KEY:-}" "nvidia" "/tmp/nv-proxy.log" \
    "nvidia/nemotron-3-ultra-550b-a55b,nvidia/nemotron-3-super-120b-a12b,nvidia/nemotron-3-nano-30b-a3b,nvidia/nemotron-3-nano-omni-30b-a3b-reasoning,nvidia/nemotron-nano-9b-v2,nvidia/llama-3.3-nemotron-super-49b-v1,nvidia/llama-3.1-nemotron-ultra-253b-v1"
}

picker() {
  local_model=$(detect_local)
  local_ctx=$(detect_local_ctx)

  echo
  bold "=== Claude Code — Provider Picker ==="
  echo

  # Local
  echo "Local (ik_llama.cpp):"
  if [ -n "$local_model" ]; then
    local ctx_info=""
    [ -n "$local_ctx" ] && ctx_info="  ctx=${local_ctx}"
    green "  1) $local_model  [port 9080${ctx_info}]"
  else
    dim  "  1) No local server detected. Start with:  ./start.sh <machine> <mode>"
  fi

  echo
  echo "Remote:"

  # Check which remote providers have keys configured
  local or_key="${OPENROUTER_API_KEY:-}"
  local nv_key="${NVIDIA_API_KEY:-}"
  local ocg_key="${OPENCODE_GO_API_KEY:-}"
  local meta

  # OpenRouter
  if [ -n "$or_key" ]; then
    meta="(key: ...${or_key: -12})"
  else
    meta="(no key — set OPENROUTER_API_KEY in ~/.secrets)"
  fi
  echo "  2) OpenRouter      ${meta}"

  # OpenCode Go
  if [ -n "$ocg_key" ]; then
    meta="(key: ...${ocg_key: -12})"
  else
    meta="(no key — set OPENCODE_GO_API_KEY in ~/.secrets)"
  fi
  echo "  3) OpenCode Go     ${meta}  [MiniMax/Qwen only]"

  # OpenCode Proxy (DeepSeek/Kimi/GLM via ocg-proxy.py)
  if [ -n "$ocg_key" ]; then
    meta="(key: ...${ocg_key: -12})"
  else
    meta="(no key — set OPENCODE_GO_API_KEY in ~/.secrets)"
  fi
  echo "  4) OpenCode Proxy  ${meta}  [DeepSeek/Kimi/GLM via local proxy]"

  # NVIDIA Proxy (NVIDIA NIM free models via ocg-proxy.py)
  if [ -n "$nv_key" ]; then
    meta="(key: ...${nv_key: -12})"
  else
    meta="(no key — set NVIDIA_API_KEY in ~/.secrets)"
  fi
  echo "  5) NVIDIA Proxy    ${meta}  [Nemotron/Llama free via local proxy]"

  echo
  read -rp "Choice [1-5]: " choice
  echo

  case "${choice:-}" in
    1) pick_local ;;
    2) pick_remote "openrouter" "${or_key:-}" "https://openrouter.ai/api" OR_MODELS ;;
    3) pick_remote "opencode-go" "${ocg_key:-}" "https://opencode.ai/zen/go" OCG_MODELS ;;
    4) pick_opencode_proxy ;;
    5) pick_nvidia_proxy ;;
    *) echo "Invalid choice."; exit 1 ;;
  esac
}

pick_local() {
  if [ -z "$local_model" ]; then
    red "No local server running."
    echo "Start one first:  ./start.sh <i9|probook|macbook-air> <mode>"
    exit 1
  fi
  local host ctx
  host=$(llama_host)
  ctx="${local_ctx:-$(detect_local_ctx)}"
  if [ -n "$ctx" ]; then
    dim "  Context size: ${ctx} tokens (from /props)"
  fi
  launch "http://${host}:9080" "dummy" "$local_model" "$local_model" \
    "local:$local_model"
}

pick_remote() {
  local provider="$1" key="$2" base_url="$3"
  local arrname="$4"
  local -a models=()
  eval "models=(\"\${${arrname}[@]}\")"

  if [ -z "$key" ]; then
    red "No API key for $provider."
    red "Set the env var in ~/.secrets and re-source it:  source ~/.secrets"
    exit 1
  fi

  bold "=== $provider models ==="
  echo
  local idx=1
  local entries=()
  for m in "${models[@]}"; do
    local id="${m%:*}"
    local name="${m##*:}"
    echo "  $idx) $name"
    dim  "      $id"
    entries+=("$id")
    ((idx++))
  done
  echo "  $idx) Custom model ID..."
  echo

  local sel
  read -rp "Choice [1-$idx]: " sel
  echo

  if [ -z "${sel:-}" ] || [ "$sel" -lt 1 ] 2>/dev/null || [ "$sel" -gt $idx ] 2>/dev/null; then
    echo "Invalid choice."; exit 1
  fi

  local model_id
  if [ "$sel" -eq $idx ]; then
    read -rp "Enter model ID: " model_id
  else
    model_id="${entries[$((sel-1))]}"
  fi

  [ -n "${model_id:-}" ] || { echo "No model ID provided."; exit 1; }

  launch "$base_url" "$key" "$model_id" "$model_id" \
    "$provider:$model_id"
}

pick_opencode_proxy() {
  local key="${OPENCODE_GO_API_KEY:-}"
  if [ -z "$key" ]; then
    red "No API key for OpenCode Go."
    red "Set OPENCODE_GO_API_KEY in ~/.secrets"
    exit 1
  fi
  start_ocg_proxy
  pick_remote "opencode-proxy" "dummy" "http://localhost:4099" OCG_PROXY_MODELS
}

pick_nvidia_proxy() {
  local key="${NVIDIA_API_KEY:-}"
  if [ -z "$key" ]; then
    red "No API key for NVIDIA."
    red "Set NVIDIA_API_KEY in ~/.secrets"
    exit 1
  fi
  start_nv_proxy
  pick_remote "nvidia-proxy" "dummy" "http://localhost:4098" NV_PROXY_MODELS
}

# ── direct launch (skip picker) ──────────────────────────────────────

direct() {
  local provider="$1" model="${2:-}"
  local base_url api_key
  shift 2 2>/dev/null || true  # consume provider + model, rest go to claude

  case "$provider" in
    local)
      local_model=$(detect_local)
      local_ctx=$(detect_local_ctx)
      if [ -z "$model" ]; then
        model="$local_model"
      fi
      if [ -z "$model" ]; then
        red "No local model running and no model specified."
        echo "Usage: $0 local <model-name>"
        echo "Start server first: ./start.sh <machine> <mode>"
        exit 1
      fi
      [ -n "$local_ctx" ] && dim "  Context size: ${local_ctx} tokens (from /props)"
      base_url="http://$(llama_host):9080"
      api_key="dummy"
      ;;
    openrouter)
      api_key="${OPENROUTER_API_KEY:-}"
      [ -z "$model" ] && { pick_remote "openrouter" "$api_key" "https://openrouter.ai/api" OR_MODELS; return; }
      base_url="https://openrouter.ai/api"
      ;;
    nvidia)
      # Route through proxy — NVIDIA NIM is OpenAI-only
      api_key="${NVIDIA_API_KEY:-}"
      [ -z "$api_key" ] && { red "Set NVIDIA_API_KEY in ~/.secrets"; exit 1; }
      start_nv_proxy
      [ -z "$model" ] && model="nvidia/nemotron-3-ultra-550b-a55b"
      base_url="http://localhost:4098"
      api_key="dummy"
      ;;
    opencode-go)
      api_key="${OPENCODE_GO_API_KEY:-}"
      [ -z "$model" ] && { pick_remote "opencode-go" "$api_key" "https://opencode.ai/zen/go" OCG_MODELS; return; }
      base_url="https://opencode.ai/zen/go"
      ;;
    opencode-proxy)
      api_key="${OPENCODE_GO_API_KEY:-}"
      start_ocg_proxy
      [ -z "$model" ] && { pick_remote "opencode-proxy" "dummy" "http://localhost:4099" OCG_PROXY_MODELS; return; }
      base_url="http://localhost:4099"
      api_key="dummy"
      ;;
    nvidia-proxy)
      api_key="${NVIDIA_API_KEY:-}"
      start_nv_proxy
      [ -z "$model" ] && { pick_remote "nvidia-proxy" "dummy" "http://localhost:4098" NV_PROXY_MODELS; return; }
      base_url="http://localhost:4098"
      api_key="dummy"
      ;;
    *)
      echo "Unknown provider: $provider" >&2
      echo "Providers: local, openrouter, nvidia, opencode-go, opencode-proxy, nvidia-proxy" >&2
      exit 1
      ;;
  esac

  [ -z "$api_key" ] && { red "No API key for $provider. Set in ~/.secrets"; exit 1; }
  launch "$base_url" "$api_key" "$model" "$model" "$provider:$model" "$@"
}

# ── main ──────────────────────────────────────────────────────────────

if [ $# -ge 1 ]; then
  direct "$@"
else
  picker
fi

#!/usr/bin/env bash
# claude-providers.sh — Claude Code provider/model picker
#   Interactive:  ./claude-providers.sh
#   Direct:       ./claude-providers.sh <provider> [model]
#
# Providers:
#   local        Local ik_llama.cpp server (auto-detects port)
#   openrouter   OpenRouter proxy (200+ models, Anthropic format)
#   nvidia       NVIDIA NIM (may not support Anthropic format natively)
#   opencode-go  OpenCode Go subscription (MiniMax/Qwen only, Anthropic format)
#
# Sources ~/.secrets for API keys (OPENROUTER_API_KEY, NVIDIA_API_KEY, OPENCODE_GO_API_KEY).
set -euo pipefail

SECRETS="$HOME/.secrets"
[ -f "$SECRETS" ] && . "$SECRETS"

# ── helpers ──────────────────────────────────────────────────────────

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

launch() {
  local base_url="$1" api_key="$2" sonnet="$3" haiku="$4" label="$5"
  echo
  bold "Launching Claude Code: $label"
  dim "  SONNET = $sonnet"
  dim "  HAIKU  = $haiku"
  dim "  URL    = $base_url"
  echo
  dim "Tip: skip the picker next time with:"
  dim "  ./claude-providers.sh ${5%%:*} ${5#*:}"
  echo
  # shellcheck disable=SC2086
  ANTHROPIC_BASE_URL="$base_url" \
  ANTHROPIC_API_KEY="$api_key" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku" \
  exec claude "$@"
}

# ── local model detection ────────────────────────────────────────────

detect_local() {
  local model
  model=$(curl -sf "http://localhost:9080/v1/models" 2>/dev/null | \
          python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || true)
  if [ -n "$model" ]; then
    echo "$model"
    return
  fi
  echo ""
}

# ── openrouter models ─────────────────────────────────────────────────

OR_MODELS=(
  "anthropic/claude-sonnet-4:Claude Sonnet 4"
  "anthropic/claude-opus-4:Claude Opus 4"
  "google/gemini-2.5-pro:Gemini 2.5 Pro"
  "deepseek/deepseek-v4-pro:DeepSeek V4 Pro"
  "qwen/qwen3.6-plus:Qwen3.6 Plus"
  "moonshotai/kimi-k2.6:Kimi K2.6"
)

# ── nvidia models ─────────────────────────────────────────────────────

NV_MODELS=(
  "nvidia/nemotron-3-super-120b-a12b:Nemotron 3 Super 120B"
  "nvidia/llama-4-maverick:Llama-4 Maverick"
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

# ── interactive picker ────────────────────────────────────────────────

picker() {
  local choice
  local docker_host_ip
  local_model=$(detect_local)
  docker_host_ip=$(ip route show default 2>/dev/null | awk '{print $3; exit}' || echo "127.0.0.1")

  echo
  bold "=== Claude Code — Provider Picker ==="
  echo

  # Local
  echo "Local (ik_llama.cpp):"
  if [ -n "$local_model" ]; then
    green "  1) $local_model  [running on port 9080]"
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

  # NVIDIA
  if [ -n "$nv_key" ]; then
    meta="(key: ...${nv_key: -12})"
  else
    meta="(no key — set NVIDIA_API_KEY in ~/.secrets)"
  fi
  echo "  3) NVIDIA NIM      ${meta}  [Anthropic format may not work]"

  # OpenCode Go
  if [ -n "$ocg_key" ]; then
    meta="(key: ...${ocg_key: -12})"
  else
    meta="(no key — set OPENCODE_GO_API_KEY in ~/.secrets)"
  fi
  echo "  4) OpenCode Go     ${meta}  [MiniMax/Qwen only]"

  echo
  read -rp "Choice [1-4]: " choice
  echo

  case "${choice:-}" in
    1) pick_local ;;
    2) pick_remote "openrouter" "${or_key:-}" "https://openrouter.ai/api/anthropic/v1" OR_MODELS[@] ;;
    3) pick_remote "nvidia" "${nv_key:-}" "https://integrate.api.nvidia.com/v1" NV_MODELS[@] ;;
    4) pick_remote "opencode-go" "${ocg_key:-}" "https://opencode.ai/zen/go/v1" OCG_MODELS[@] ;;
    *) echo "Invalid choice."; exit 1 ;;
  esac
}

pick_local() {
  if [ -z "$local_model" ]; then
    red "No local server running."
    echo "Start one first:  ./start.sh <i9|probook|macbook-air> <mode>"
    exit 1
  fi
  docker_host_ip=$(ip route show default 2>/dev/null | awk '{print $3; exit}' || echo "127.0.0.1")
  launch "http://${docker_host_ip}:9080/v1" "dummy" "$local_model" "$local_model" \
    "local:$local_model"
}

pick_remote() {
  local provider="$1" key="$2" base_url="$3"
  local -n models="$4"

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
    local id="${m%%:*}"
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

# ── direct launch (skip picker) ──────────────────────────────────────

direct() {
  local provider="$1" model="${2:-}"
  local base_url api_key docker_host_ip

  case "$provider" in
    local)
      local_model=$(detect_local)
      docker_host_ip=$(ip route show default 2>/dev/null | awk '{print $3; exit}' || echo "127.0.0.1")
      if [ -z "$model" ]; then
        model="$local_model"
      fi
      if [ -z "$model" ]; then
        red "No local model running and no model specified."
        echo "Usage: $0 local <model-name>"
        echo "Start server first: ./start.sh <machine> <mode>"
        exit 1
      fi
      base_url="http://${docker_host_ip}:9080/v1"
      api_key="dummy"
      ;;
    openrouter)
      api_key="${OPENROUTER_API_KEY:-}"
      [ -z "$model" ] && { pick_remote "openrouter" "$api_key" "https://openrouter.ai/api/anthropic/v1" OR_MODELS[@]; return; }
      base_url="https://openrouter.ai/api/anthropic/v1"
      ;;
    nvidia)
      api_key="${NVIDIA_API_KEY:-}"
      [ -z "$model" ] && { pick_remote "nvidia" "$api_key" "https://integrate.api.nvidia.com/v1" NV_MODELS[@]; return; }
      base_url="https://integrate.api.nvidia.com/v1"
      ;;
    opencode-go)
      api_key="${OPENCODE_GO_API_KEY:-}"
      [ -z "$model" ] && { pick_remote "opencode-go" "$api_key" "https://opencode.ai/zen/go/v1" OCG_MODELS[@]; return; }
      base_url="https://opencode.ai/zen/go/v1"
      ;;
    *)
      echo "Unknown provider: $provider" >&2
      echo "Providers: local, openrouter, nvidia, opencode-go" >&2
      exit 1
      ;;
  esac

  [ -z "$api_key" ] && { red "No API key for $provider. Set in ~/.secrets"; exit 1; }
  launch "$base_url" "$api_key" "$model" "$model" "$provider:$model"
}

# ── main ──────────────────────────────────────────────────────────────

if [ $# -ge 1 ]; then
  direct "$@"
else
  picker
fi

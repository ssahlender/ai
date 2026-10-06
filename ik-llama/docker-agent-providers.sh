#!/usr/bin/env bash
# docker-agent-providers.sh — Interactive model & provider launcher for docker-agent
#
# Usage:
#   Interactive picker:  ./docker-agent-providers.sh [docker-agent flags/prompt]
#   Direct launch:       ./docker-agent-providers.sh <provider> [model] [flags/prompt]
#
# Providers:
#   local          Local ik_llama.cpp server (http://localhost:9080/v1)
#   opencode-go    OpenCode Go models (Qwen, DeepSeek, Kimi, GLM, MiniMax)
#   openrouter     OpenRouter models
#
# Examples:
#   ./docker-agent-providers.sh
#   ./docker-agent-providers.sh local
#   ./docker-agent-providers.sh opencode-go qwen3.7-max
#   ./docker-agent-providers.sh opencode-go deepseek-v4-pro --exec "reverse a list"
set -euo pipefail

# ── early help ───────────────────────────────────────────────────────
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "Usage:"
  echo "  $0                                  Interactive model picker"
  echo "  $0 local [flags/prompt]             Use active local llama-server model"
  echo "  $0 opencode-go [model] [args...]    Use OpenCode Go model (default: qwen3.7-max)"
  echo "  $0 openrouter [model] [args...]     Use OpenRouter model"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="$HOME/.secrets"
if [ -f "$SECRETS" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$SECRETS"
  set +a
fi

DOCKER_AGENT_BIN="$(command -v docker-agent || command -v cagent || echo "$HOME/brewenv/docker-agent")"
if [ ! -x "$DOCKER_AGENT_BIN" ]; then
  echo "Error: docker-agent (or cagent) binary not found. Install or add to PATH." >&2
  exit 1
fi

# Ensure OPENCODE_API_KEY is available in env if only OPENCODE_GO_API_KEY was set
if [ -z "${OPENCODE_API_KEY:-}" ] && [ -n "${OPENCODE_GO_API_KEY:-}" ]; then
  export OPENCODE_API_KEY="$OPENCODE_GO_API_KEY"
fi

# ── styling helpers ──────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

# ── local detection ──────────────────────────────────────────────────
llama_host() {
  echo "${IK_LLAMA_HOST:-127.0.0.1}"
}

detect_local() {
  local model host port="${IK_LLAMA_PORT:-9080}"
  host=$(llama_host)
  model=$(curl -sf --max-time 3 --connect-timeout 2 "http://${host}:${port}/v1/models" 2>/dev/null | \
          python3 -c "
import sys, json, os
d = json.load(sys.stdin)
full = d['data'][0]['id']
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

# ── curated model lists ──────────────────────────────────────────────
# shellcheck disable=SC2034
OCG_MODELS=(
  "qwen3.7-max:Qwen 3.7 Max (flagship coding & reasoning)"
  "qwen3.7-plus:Qwen 3.7 Plus (fast coding)"
  "deepseek-v4-pro:DeepSeek V4 Pro (reasoning & coding)"
  "deepseek-v4-flash:DeepSeek V4 Flash (ultra fast)"
  "kimi-k2.6:Kimi K2.6 (long context)"
  "kimi-k3:Kimi K3"
  "glm-5.3:GLM 5.3"
  "minimax-m3:MiniMax M3"
)

# shellcheck disable=SC2034
OR_MODELS=(
  "meta-llama/llama-4-maverick:Llama 4 Maverick"
  "google/gemini-2.5-pro:Gemini 2.5 Pro"
  "anthropic/claude-sonnet-4:Claude Sonnet 4"
  "deepseek/deepseek-v4-pro:DeepSeek V4 Pro"
)

# ── launch helper ────────────────────────────────────────────────────
launch() {
  local model_ref="$1" tip_prov="$2" tip_model="$3"
  shift 3

  echo
  bold "Launching Docker Agent: $model_ref"
  dim "Tip: skip the picker next time with:"
  if [ -n "$tip_model" ]; then
    dim "  $0 $tip_prov $tip_model"
  else
    dim "  $0 $tip_prov"
  fi
  echo

  local args=("$@")
  local flags=()
  local positionals=()
  local skip_next=0
  local has_agent=0

  for ((i=0; i<${#args[@]}; i++)); do
    local arg="${args[i]}"
    if [ "$skip_next" -eq 1 ]; then
      flags+=("$arg")
      skip_next=0
      continue
    fi
    case "$arg" in
      -a|--agent)
        flags+=("$arg")
        skip_next=1
        has_agent=1
        ;;
      -a=*|--agent=*)
        flags+=("$arg")
        has_agent=1
        ;;
      --agent-picker|--app-name|--attach|--disable-commands|--env-from-file|\
      --fake|--fake-stream|--flavor|--hook-*|--kit|--kit-arg|--mcp-oauth-redirect-uri|\
      --model|--models-gateway|--on-event|--prompt-file|--record|--remote|\
      --safety|--sandbox-kit|--sandbox-ttl|--session|-s|--session-db|--template|\
      --theme|--working-dir|-w|--worktree|--worktree-base|--worktree-pr)
        flags+=("$arg")
        skip_next=1
        ;;
      --*|-*)
        flags+=("$arg")
        ;;
      *)
        positionals+=("$arg")
        ;;
    esac
  done

  # Docker Agent syntax: docker-agent run [flags] [agent] [message]
  # If no agent was explicitly named, insert built-in 'coder' before prompt
  if [ "$has_agent" -eq 0 ]; then
    if [ ${#positionals[@]} -eq 0 ]; then
      positionals=("coder")
    elif [ "${positionals[0]}" != "coder" ] && [ ! -f "${positionals[0]}" ]; then
      positionals=("coder" "${positionals[@]}")
    fi
  fi

  exec "$DOCKER_AGENT_BIN" run --model "$model_ref" ${flags[@]+"${flags[@]}"} ${positionals[@]+"${positionals[@]}"}
}

# ── pickers ──────────────────────────────────────────────────────────
pick_local() {
  local local_model
  local_model=$(detect_local)
  if [ -z "$local_model" ]; then
    red "No local llama-server running on port ${IK_LLAMA_PORT:-9080}."
    echo "Start a local model first in another terminal:"
    dim  "  cd $SCRIPT_DIR && ./start.sh i9 1"
    exit 1
  fi

  green "Detected local model: $local_model"
  launch "ik-llama/$local_model" "local" "" "$@"
}

pick_remote() {
  local provider="$1" arrname="$2"
  shift 2
  local -a models=()
  eval "models=(\"\${${arrname}[@]}\")"

  bold "=== $provider models ==="
  echo
  local idx=1
  local entries=()
  for m in "${models[@]}"; do
    local id="${m%%:*}"
    local desc="${m#*:}"
    printf "  %2d) %-26s %s\n" "$idx" "$id" "$(dim "($desc)")"
    entries+=("$id")
    idx=$((idx + 1))
  done
  printf "  %2d) Custom model ID...\n" "$idx"
  echo

  local sel
  read -rp "Choice [1-$idx]: " sel
  echo

  if [[ ! "${sel:-}" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "$idx" ]; then
    red "Invalid choice."; exit 1
  fi

  local model_id
  if [ "$sel" -eq "$idx" ]; then
    read -rp "Enter model ID: " model_id
  else
    model_id="${entries[$((sel-1))]}"
  fi

  [ -n "${model_id:-}" ] || { red "No model ID provided."; exit 1; }

  launch "${provider}/${model_id}" "$provider" "$model_id" "$@"
}

# ── main picker menu ─────────────────────────────────────────────────
picker() {
  local local_model
  local_model=$(detect_local)

  echo
  bold "=== Docker AI Agent — Provider & Model Picker ==="
  echo

  # 1. Local
  echo "Local (ik_llama.cpp):"
  if [ -n "$local_model" ]; then
    green "  1) $local_model  [port ${IK_LLAMA_PORT:-9080} ONLINE]"
  else
    dim   "  1) (offline) Start with:  cd $SCRIPT_DIR && ./start.sh i9 1"
  fi

  echo
  echo "Cloud / API Providers:"

  # 2. OpenCode Go
  local ocg_key="${OPENCODE_API_KEY:-${OPENCODE_GO_API_KEY:-}}"
  local ocg_meta
  if [ -n "$ocg_key" ]; then
    ocg_meta="$(green "configured")"
  else
    ocg_meta="$(dim "no key in ~/.secrets")"
  fi
  echo "  2) OpenCode Go     [${ocg_meta}]  (Qwen 3.7, DeepSeek V4, Kimi, GLM)"

  # 3. OpenRouter
  local or_key="${OPENROUTER_API_KEY:-}"
  local or_meta
  if [ -n "$or_key" ]; then
    or_meta="$(green "configured")"
  else
    or_meta="$(dim "no key in ~/.secrets")"
  fi
  echo "  3) OpenRouter      [${or_meta}]  (Llama 4, Gemini 2.5, Claude Sonnet 4)"

  echo
  read -rp "Choice [1-3]: " choice
  echo

  case "${choice:-}" in
    1) pick_local "$@" ;;
    2) pick_remote "opencode-go" OCG_MODELS "$@" ;;
    3) pick_remote "openrouter" OR_MODELS "$@" ;;
    *) red "Invalid choice."; exit 1 ;;
  esac
}

# ── argument handling (direct vs picker) ─────────────────────────────
if [ $# -eq 0 ]; then
  picker
  exit 0
fi

case "$1" in
  local)
    shift
    local_model=$(detect_local)
    if [ -z "$local_model" ]; then
      red "No local llama-server running on port ${IK_LLAMA_PORT:-9080}."
      echo "Start one first:  cd $SCRIPT_DIR && ./start.sh i9 1"
      exit 1
    fi
    # If the user passed the detected model name explicitly, consume it
    if [ $# -gt 0 ] && [ "$1" = "$local_model" ]; then
      shift
    fi
    launch "ik-llama/$local_model" "local" "" "$@"
    ;;
  opencode-go)
    shift
    model="qwen3.7-max"
    if [ $# -gt 0 ] && [[ "$1" != -* ]] && [[ "$1" =~ ^[A-Za-z0-9._/:-]+$ ]]; then
      model="$1"
      shift
    fi
    launch "opencode-go/$model" "opencode-go" "$model" "$@"
    ;;
  openrouter)
    shift
    model="meta-llama/llama-4-maverick"
    if [ $# -gt 0 ] && [[ "$1" != -* ]] && [[ "$1" =~ ^[A-Za-z0-9._/:-]+$ ]]; then
      model="$1"
      shift
    fi
    launch "openrouter/$model" "openrouter" "$model" "$@"
    ;;
  *)
    # Flags or prompt forwarded to picker if starting with dash; reject unknown commands
    if [[ "$1" =~ ^- ]]; then
      picker "$@"
    else
      red "Unknown provider or option: '$1'."
      echo "Usage: $0 [local|opencode-go|openrouter] [model] [args...]" >&2
      exit 1
    fi
    ;;
esac

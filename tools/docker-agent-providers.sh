#!/usr/bin/env bash
# docker-agent-providers.sh — Interactive model & provider launcher for docker-agent
#
# Usage:
#   Interactive picker:  ./docker-agent-providers.sh [docker-agent flags/prompt]
#   Direct launch:       ./docker-agent-providers.sh <provider> [model] [flags/prompt]
#
# Providers:
#   local          The local model (llama-swap chain, or a bare llama-server on 9080)
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
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_local-llm.sh"

# ── pickers ──────────────────────────────────────────────────────────
pick_local() {
  local local_model
  local_model=$(detect_local)
  if [ -z "$local_model" ]; then
    red "No local model found (llama-swap on ${IK_LLAMA_SWAP_PORT:-9082} or llama-server on ${IK_LLAMA_PORT:-9080})."
    echo "Start a local model first in another terminal:"
    dim  "  $SCRIPT_DIR/../llm/llama-swap-setup.sh"
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
    green "  1) $local_model  [port $(local_upstream_port) ONLINE]"
  else
    dim   "  1) (offline) Start with:  $SCRIPT_DIR/../llm/llama-swap-setup.sh"
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
      red "No local model found (llama-swap on ${IK_LLAMA_SWAP_PORT:-9082} or llama-server on ${IK_LLAMA_PORT:-9080})."
      echo "Start one first:  $SCRIPT_DIR/../llm/llama-swap-setup.sh"
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

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

cd "$(dirname "$0")"

run() {
  echo "==> $*"
  "$@"
}

run ./nvm-update.sh
run ./claude-update.sh
run ./opencode-update.sh
run ./codex-update.sh
run ./hf-update.sh
run ./hermes-update.sh
run ./rtk-update.sh
run ./context-mode-update.sh
run ./claude-mem-update.sh

# Ollama is only present on machines that use it (Mac, etc.)
if command -v ollama >/dev/null 2>&1; then
  run ./ollama-update.sh
  run ./ollama-models-update.sh
fi

# Upgrade all brew packages (casks + formulas)
if [ -n "$IS_I9" ] || command -v brew >/dev/null 2>&1; then
  $BREW upgrade
fi

# Clean up old brew versions to prevent disk bloat
if [ -n "$IS_I9" ] || command -v brew >/dev/null 2>&1; then
  $BREW cleanup --prune=all
fi

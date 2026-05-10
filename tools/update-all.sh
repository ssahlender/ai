#!/usr/bin/env bash
set -euo pipefail

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

# Ollama is only present on machines that use it (Mac, etc.)
if command -v ollama >/dev/null 2>&1; then
  run ./ollama-update.sh
  run ./ollama-models-update.sh
fi

# Clean up old brew versions to prevent disk bloat
if command -v brew >/dev/null 2>&1; then
  if [ -n "$IS_I9" ]; then
    echo "Run manually on this machine:"
    echo "  $BREW cleanup --prune=all"
  else
    $BREW cleanup --prune=all
  fi
fi

#!/usr/bin/env bash
set -euo pipefail

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
  brew cleanup --prune=all
fi

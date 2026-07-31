#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

cd "$(dirname "$0")"

run() {
  echo "==> $*"
  "$@"
}

UPDATE_TOOLS=(
  nvm
  claude
  opencode
  codex
  antigravity
  hf
  hermes
  rtk
  context-mode
  claude-mem
  graphify
  pi
  repomix
  ccusage
  headroom
  mattpocock-skills
)

for tool in "${UPDATE_TOOLS[@]}"; do
  script="./${tool}-update.sh"
  if [ -x "$script" ]; then
    run "$script"
  else
    echo "$script missing — skipping"
  fi
done

# Ollama is only present on machines that use it (Mac, etc.)
if command -v ollama >/dev/null 2>&1; then
  run ./ollama-update.sh
  run ./ollama-models-update.sh
fi

# Upgrade all brew packages (casks + formulas)
if [ -n "$IS_I9" ] || command -v brew >/dev/null 2>&1; then
  $BREW upgrade || echo "brew upgrade failed (sudo timeout?) — skipping"
fi

# Clean up old brew versions to prevent disk bloat
if [ -n "$IS_I9" ] || command -v brew >/dev/null 2>&1; then
  $BREW cleanup --prune=all || echo "brew cleanup failed — skipping"
fi

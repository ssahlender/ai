#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

if [ -n "$IS_I9" ]; then
  echo "Skipping on i9 — Ollama is too slow on CPU. Use ik_llama.cpp."
  exit 0
fi

_brew_install ollama

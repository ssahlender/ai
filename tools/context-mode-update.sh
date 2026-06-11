#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_npm-wrapper.sh"

if ! command -v context-mode >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/context-mode" ]; then
  echo "context-mode not installed — skipping"
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found — skipping context-mode update"
  exit 0
fi

_npm_update_g context-mode
"$(dirname "${BASH_SOURCE[0]}")/context-mode-init.sh"

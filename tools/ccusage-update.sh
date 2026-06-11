#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_npm-wrapper.sh"

if ! command -v ccusage >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/ccusage" ]; then
  echo "ccusage not installed — skipping"
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found — skipping ccusage update"
  exit 0
fi

_npm_update_g ccusage

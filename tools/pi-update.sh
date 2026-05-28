#!/usr/bin/env bash
# Updates Pi Coding Agent via Homebrew, then refreshes Pi packages.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

FORMULA="pi-coding-agent"

if ! $BREW list --formula "$FORMULA" &>/dev/null; then
  echo "pi-coding-agent not installed — skipping"
  exit 0
fi

$BREW upgrade "$FORMULA" || true
"$(dirname "${BASH_SOURCE[0]}")/pi-init.sh"

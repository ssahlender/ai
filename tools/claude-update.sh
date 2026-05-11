#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if $BREW list --cask claude-code &>/dev/null; then
  $BREW upgrade --cask claude-code
else
  echo "claude-code not installed — skipping"
fi

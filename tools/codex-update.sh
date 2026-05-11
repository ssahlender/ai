#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if $BREW list --cask codex &>/dev/null; then
  $BREW upgrade --cask codex
else
  echo "codex not installed — skipping"
fi

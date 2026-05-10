#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if [ -n "$IS_I9" ]; then
  echo "Run manually on this machine:"
  if $BREW list --cask codex &>/dev/null; then
    echo "  $BREW update && $BREW upgrade --cask codex"
  else
    echo "  $BREW update && $BREW install --cask codex"
  fi
  exit 0
fi

if $BREW list --cask codex &>/dev/null; then
  $BREW upgrade --cask codex
else
  $BREW install --cask codex
fi

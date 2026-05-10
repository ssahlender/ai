#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if [ -n "$IS_I9" ]; then
  echo "Run manually on this machine:"
  if $BREW list --cask claude-code &>/dev/null; then
    echo "  $BREW update && $BREW upgrade --cask claude-code"
  else
    echo "  $BREW update && $BREW install --cask claude-code"
  fi
  exit 0
fi

if $BREW list --cask claude-code &>/dev/null; then
  $BREW upgrade --cask claude-code
else
  $BREW install --cask claude-code
fi

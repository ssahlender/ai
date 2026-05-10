#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if [ -n "$IS_I9" ]; then
  echo "Run manually on this machine:"
  if $BREW list --formula opencode &>/dev/null; then
    echo "  $BREW update && $BREW upgrade opencode"
  else
    echo "  $BREW update && $BREW install opencode"
  fi
  exit 0
fi

if $BREW list --formula opencode &>/dev/null; then
  $BREW upgrade opencode
else
  $BREW install opencode
fi

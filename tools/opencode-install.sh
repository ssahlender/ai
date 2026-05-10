#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if [ -n "$IS_I9" ]; then
  echo "Run manually on this machine:"
  echo "  $BREW update && $BREW install opencode"
  exit 0
fi

$BREW install opencode

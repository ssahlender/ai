#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if $BREW list --formula opencode &>/dev/null; then
  $BREW upgrade opencode
else
  echo "opencode not installed — skipping"
fi

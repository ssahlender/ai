#!/usr/bin/env bash
# Installs the Hugging Face CLI via Homebrew.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if [ -n "$IS_I9" ]; then
  echo "Run manually on this machine:"
  echo "  $BREW update && $BREW install hf"
  exit 0
fi

$BREW install hf

#!/usr/bin/env bash
# Installs or updates the Hugging Face CLI via Homebrew.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

FORMULA="hf"

if [ -n "$IS_I9" ]; then
  current=$(hf version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "not installed")
  echo "Current version: $current"
  echo "Run manually on this machine:"
  if [[ "$current" == "not installed" ]]; then
    echo "  $BREW update && $BREW install $FORMULA"
  else
    echo "  $BREW update && $BREW upgrade $FORMULA"
  fi
  exit 0
fi

if ! $BREW list --formula "$FORMULA" &>/dev/null; then
  echo "Installing Hugging Face CLI..."
  $BREW install "$FORMULA"
else
  current=$(hf version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  echo "Updating Hugging Face CLI (installed: $current)..."
  $BREW upgrade "$FORMULA" || true
fi

echo "Version: $(hf version 2>/dev/null | head -1 || echo 'unknown')"

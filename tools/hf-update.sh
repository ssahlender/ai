#!/usr/bin/env bash
# Installs or updates the Hugging Face CLI via Homebrew.
set -euo pipefail

FORMULA="hf"

# On the i9 (native Linux, company proxy) brew commands need the proxy-aware aliases
if [[ "$(uname -s)" == "Linux" ]] && ! grep -qi "microsoft" /proc/version 2>/dev/null; then
  current=$(hf version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "not installed")
  echo "Current version: $current"
  echo "Run manually on this machine:"
  if [[ "$current" == "not installed" ]]; then
    echo "  brewupd && brew install $FORMULA"
  else
    echo "  brewupd && brewupg $FORMULA"
  fi
  exit 0
fi

if ! brew list --formula "$FORMULA" &>/dev/null; then
  echo "Installing Hugging Face CLI..."
  brew install "$FORMULA"
else
  current=$(hf version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  echo "Updating Hugging Face CLI (installed: $current)..."
  brew upgrade "$FORMULA" || true
fi

echo "Version: $(hf version 2>/dev/null | head -1 || echo 'unknown')"

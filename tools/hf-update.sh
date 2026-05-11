#!/usr/bin/env bash
# Updates the Hugging Face CLI via Homebrew. Skips if not installed.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

FORMULA="hf"

if ! $BREW list --formula "$FORMULA" &>/dev/null; then
  echo "hf not installed — skipping"
  exit 0
fi

current=$(hf version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
echo "Updating Hugging Face CLI (installed: $current)..."
$BREW upgrade "$FORMULA" || true
echo "Version: $(hf version 2>/dev/null | head -1 || echo 'unknown')"

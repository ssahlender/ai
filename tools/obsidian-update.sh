#!/usr/bin/env bash
# Upgrades Obsidian via the Homebrew cask. Skips if not installed.
# The cask is marked auto_updates, so a plain `brew upgrade` skips it; --greedy forces it.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_obsidian-common.sh"

if ! $BREW list --cask obsidian &>/dev/null; then
  echo "obsidian not installed — skipping"
  exit 0
fi

if [ "$(uname -s)" = "Linux" ]; then
  obsidian_prepare_appimage_dir
  $BREW upgrade --cask --greedy obsidian "${OBSIDIAN_BREW_FLAGS[@]}" || true
  obsidian_write_launcher
else
  $BREW upgrade --cask --greedy obsidian || true
fi

echo "obsidian: $($BREW list --cask --versions obsidian 2>/dev/null || echo unknown)"

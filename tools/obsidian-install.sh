#!/usr/bin/env bash
# Installs Obsidian (Markdown vault viewer) via the Homebrew cask.
# Used for READ-ONLY browsing of Markdown wikis (graph view, backlinks); agents stay
# the writers. Keep sync, publish and community plugins off for sensitive vaults.
#
# Linux: the cask is an AppImage. On the i9, brew runs as a separate user whose home is
# not readable, so the AppImage is placed in the brew prefix instead and a launcher is
# written to ~/.local/bin/obsidian.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_obsidian-common.sh"

if [ -z "${IS_I9:-}" ] && ! command -v brew >/dev/null 2>&1; then
  echo "brew not found — install Homebrew first, or download Obsidian from obsidian.md" >&2
  exit 1
fi

if [ "$(uname -s)" = "Linux" ]; then
  obsidian_prepare_appimage_dir
  if $BREW list --cask obsidian &>/dev/null && [ ! -x "$OBSIDIAN_APPIMAGE" ]; then
    echo "Obsidian cask present but AppImage not in $OBSIDIAN_APPIMAGE_DIR — reinstalling there"
    $BREW reinstall --cask obsidian "${OBSIDIAN_BREW_FLAGS[@]}"
  elif ! $BREW list --cask obsidian &>/dev/null; then
    $BREW install --cask obsidian "${OBSIDIAN_BREW_FLAGS[@]}"
  else
    echo "Obsidian already installed: $OBSIDIAN_APPIMAGE"
  fi
  obsidian_write_launcher
else
  $BREW list --cask obsidian &>/dev/null || $BREW install --cask obsidian
fi

echo "Obsidian installed."
echo "Safe use for sensitive vaults: no Sync/Publish, no community plugins, open the vault read-only."

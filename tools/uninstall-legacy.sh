#!/usr/bin/env bash
# Cleans up AI tools installed outside Homebrew (curl|bash, npm, etc.)
# so they can be reinstalled via brew. Safe to run on any machine —
# skips tools already managed by brew.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

changed=0
needs_sudo=()

uninstall_if_not_brew() {
  local bin_name="$1" brew_name="$2" brew_type="${3:-formula}"  # formula | cask

  local bin
  bin=$(command -v "$bin_name" 2>/dev/null || true)
  if [ -z "$bin" ]; then
    echo "  $bin_name: not installed"
    return
  fi

  # Check if already managed by brew
  if command -v brew >/dev/null 2>&1; then
    if [ "$brew_type" = "cask" ] && $BREW list --cask "$brew_name" &>/dev/null; then
      echo "  $bin_name: managed by brew (cask) — skipping"
      return
    elif [ "$brew_type" = "formula" ] && $BREW list --formula "$brew_name" &>/dev/null; then
      echo "  $bin_name: managed by brew (formula) — skipping"
      return
    fi
  fi

  echo "  $bin_name: found at $bin (not managed by brew) — removing..."
  if rm -f "$bin" 2>/dev/null; then
    echo "  $bin_name: removed"
    changed=$((changed + 1))
  else
    echo "  $bin_name: permission denied (queued for sudo)"
    needs_sudo+=("$bin")
  fi
}

echo "Removing non-brew installations..."
echo

uninstall_if_not_brew claude   claude-code cask
uninstall_if_not_brew opencode opencode    formula
uninstall_if_not_brew codex    codex       cask
uninstall_if_not_brew ollama   ollama      formula

if [ ${#needs_sudo[@]} -gt 0 ]; then
  echo
  echo "${#needs_sudo[@]} need(s) root. Run:"
  echo "  sudo rm -f ${needs_sudo[*]}"
  changed=$((changed + ${#needs_sudo[@]}))
fi

echo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$changed" -gt 0 ]; then
  echo "$changed tool(s) removed. Reinstall with brew:"
  if [ -n "$IS_I9" ]; then
    echo "  cd $SCRIPT_DIR && $BREW update && $BREW install claude-code opencode codex"
  else
    echo "  cd $SCRIPT_DIR && $BREW install --cask claude-code && $BREW install opencode && $BREW install --cask codex"
  fi
else
  echo "Nothing to remove — all tools already managed by brew or not installed."
fi

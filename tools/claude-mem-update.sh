#!/usr/bin/env bash
set -euo pipefail

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found — skipping claude-mem update"
  exit 0
fi

if [ -d "$HOME/.claude-mem" ] || [ -d "$HOME/.claude/plugins/marketplaces/thedotmack" ]; then
  current_version="$(npx -y claude-mem@latest version 2>/dev/null || true)"
  if [ -n "$current_version" ]; then
    echo "claude-mem available version: $current_version"
  fi

  if [ "${CLAUDE_MEM_UPDATE_REINSTALL:-0}" = "1" ]; then
    "$(dirname "${BASH_SOURCE[0]}")/claude-mem-install.sh"
  else
    echo "claude-mem reinstall skipped — upstream update/install is interactive."
    echo "Set CLAUDE_MEM_UPDATE_REINSTALL=1 to reinstall intentionally."
  fi
else
  echo "claude-mem not installed — skipping"
fi

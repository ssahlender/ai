#!/usr/bin/env bash
set -euo pipefail

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found — skipping claude-mem update"
  exit 0
fi

if [ -d "$HOME/.claude-mem" ] || [ -d "$HOME/.claude/plugins/marketplaces/thedotmack" ]; then
  "$(dirname "${BASH_SOURCE[0]}")/claude-mem-install.sh"
else
  echo "claude-mem not installed — skipping"
fi

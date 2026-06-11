#!/usr/bin/env bash
# Updates Antigravity CLI. The binary self-updates in the background during
# regular use, so this script only reports the current version.
set -euo pipefail

AGY_BIN="${HOME}/.local/bin/agy"

if [ ! -f "$AGY_BIN" ] && ! command -v agy >/dev/null 2>&1; then
  echo "Antigravity CLI not installed — skipping"
  exit 0
fi

echo "Antigravity CLI self-updates in the background during regular use."
echo "Current version: $("$AGY_BIN" version 2>/dev/null || echo 'unknown')"

# Refresh shell integration (harmless if already configured)
if [ -x "$AGY_BIN" ]; then
  "$AGY_BIN" install || true
fi

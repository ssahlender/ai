#!/usr/bin/env bash
set -euo pipefail

if ! command -v context-mode >/dev/null 2>&1; then
  echo "context-mode not installed — skipping"
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found — skipping context-mode update"
  exit 0
fi

npm update -g context-mode
"$(dirname "${BASH_SOURCE[0]}")/context-mode-init.sh"

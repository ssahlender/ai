#!/usr/bin/env bash
set -euo pipefail

if command -v brew >/dev/null 2>&1; then
  brew update
  brew upgrade --cask codex
  brew cleanup --prune=all
else
  echo "run brewupd + brewupg"
fi

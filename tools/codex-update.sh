#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  echo "Run manually on this machine:"
  if brew list --cask codex &>/dev/null; then
    echo "  brewupd && brew upgrade --cask codex"
  else
    echo "  brewupd && brew install --cask codex"
  fi
  exit 0
fi

if brew list --cask codex &>/dev/null; then
  brew upgrade --cask codex
else
  brew install --cask codex
fi

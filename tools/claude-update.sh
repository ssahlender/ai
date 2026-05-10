#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  echo "Run manually on this machine:"
  if brew list --cask claude-code &>/dev/null; then
    echo "  brewupd && brew upgrade --cask claude-code"
  else
    echo "  brewupd && brew install --cask claude-code"
  fi
  exit 0
fi

if brew list --cask claude-code &>/dev/null; then
  brew upgrade --cask claude-code
else
  brew install --cask claude-code
fi

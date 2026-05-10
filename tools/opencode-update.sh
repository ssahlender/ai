#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  echo "Run manually on this machine:"
  if brew list --formula opencode &>/dev/null; then
    echo "  brewupd && brew upgrade opencode"
  else
    echo "  brewupd && brew install opencode"
  fi
  exit 0
fi

if brew list --formula opencode &>/dev/null; then
  brew upgrade opencode
else
  brew install opencode
fi

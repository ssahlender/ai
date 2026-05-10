#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  echo "Run manually on this machine:"
  echo "  brewupd && brew upgrade --cask claude-code"
  exit 0
fi

brew upgrade --cask claude-code

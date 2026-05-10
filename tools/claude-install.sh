#!/usr/bin/env bash
set -euo pipefail

# On the i9 (company proxy), brew needs proxy-aware aliases
if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  echo "Run manually on this machine:"
  echo "  brewupd && brew install --cask claude-code"
  exit 0
fi

brew install --cask claude-code

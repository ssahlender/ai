#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  echo "Run manually on this machine:"
  echo "  brewupd && brew install opencode"
  exit 0
fi

brew install opencode

#!/usr/bin/env bash
# Installs the Hugging Face CLI via Homebrew.
set -euo pipefail

# On the i9 (company proxy) brew commands need the proxy-aware aliases
if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  echo "Run manually on this machine:"
  echo "  brewupd && brew install hf"
  exit 0
fi

brew install hf

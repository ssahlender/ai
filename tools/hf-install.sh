#!/usr/bin/env bash
# Installs the Hugging Face CLI via Homebrew.
set -euo pipefail

# On the i9 (native Linux, company proxy) brew commands need the proxy-aware aliases
if [[ "$(uname -s)" == "Linux" ]] && ! grep -qi "microsoft" /proc/version 2>/dev/null; then
  echo "Run manually on this machine:"
  echo "  brewupd && brew install hf"
  exit 0
fi

brew install hf

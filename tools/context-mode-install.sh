#!/usr/bin/env bash
set -euo pipefail

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found. Install Node/npm first, for example with ./nvm-install.sh."
  exit 1
fi

npm install -g context-mode
"$(dirname "${BASH_SOURCE[0]}")/context-mode-init.sh"

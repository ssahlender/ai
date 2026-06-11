#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_npm-wrapper.sh"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found. Install Node/npm first, for example with ./nvm-install.sh."
  exit 1
fi

_npm_install_g ccusage

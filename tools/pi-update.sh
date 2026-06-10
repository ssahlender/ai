#!/usr/bin/env bash
# Updates Pi Coding Agent. Falls back to npm on Debian 12 (brew glibc issue).
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

FORMULA="pi-coding-agent"
NPM_PKG="@earendil-works/pi-coding-agent"

if $BREW list --formula "$FORMULA" &>/dev/null; then
  $BREW upgrade "$FORMULA" || true
elif npm list -g "$NPM_PKG" &>/dev/null; then
  echo "pi found via npm — upgrading"
  npm update -g "$NPM_PKG"
else
  echo "pi-coding-agent not installed — skipping"
  exit 0
fi

"$(dirname "${BASH_SOURCE[0]}")/pi-init.sh"

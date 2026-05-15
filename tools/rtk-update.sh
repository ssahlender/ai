#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if $BREW list --formula rtk &>/dev/null; then
  $BREW upgrade rtk
  "$(dirname "${BASH_SOURCE[0]}")/rtk-init.sh"
else
  echo "rtk not installed — skipping"
fi

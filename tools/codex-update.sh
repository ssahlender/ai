#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex not installed — skipping"
  exit 0
fi

_brew_upgrade codex --cask

# Enforce on every run, including upgrades that are already current.
bash "$(dirname "${BASH_SOURCE[0]}")/disable-remote-control.sh" codex

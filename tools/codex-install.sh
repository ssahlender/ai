#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

_brew_install --cask codex

# Enforce on every run, including upgrades that are already current.
bash "$(dirname "${BASH_SOURCE[0]}")/disable-remote-control.sh" codex

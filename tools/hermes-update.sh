#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if $BREW list --formula hermes-agent &>/dev/null; then
  $BREW upgrade hermes-agent
else
  $BREW install hermes-agent
fi

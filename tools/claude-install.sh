#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

$BREW install --cask claude-code

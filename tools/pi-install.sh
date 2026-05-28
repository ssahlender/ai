#!/usr/bin/env bash
# Installs Pi Coding Agent via Homebrew, then installs Pi packages.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

$BREW install pi-coding-agent
"$(dirname "${BASH_SOURCE[0]}")/pi-init.sh"

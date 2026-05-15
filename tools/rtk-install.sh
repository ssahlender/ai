#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

$BREW install rtk
"$(dirname "${BASH_SOURCE[0]}")/rtk-init.sh"

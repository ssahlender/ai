#!/usr/bin/env bash
# Installs the Hugging Face CLI via Homebrew.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

$BREW install hf
